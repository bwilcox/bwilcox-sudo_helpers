#!/usr/bin/ruby
#
#  This script attempts to parse a puppet manifest and determine
#  what commands need to be placed into the sudoers file to enable
#  successful operation.
#
#  The theory is that every manifest item is just a hash of key/value
#  pairs.  We pull out those hashes and then fill in the blanks for 
#  the commands used to perform the actions.
#
#  2013-05-28  Bill W. Initial program
#  2013-07-08  Bill W. Work on abstracting the commands.  I want to 
#       list all of the commands in the providers for the modules and 
#       have this script reference the commands there to produce
#       the lines for sudoers.
#  2013-07-10  Bill W. Added options to specify the provider and to 
#       toggle debug.
#  2013-07-11  Bill W. Refactored sudo_file processing.  Added white and
#       black lists for commands.
#  2013-07-23  Bill W. Refactored sudo_package and sudo_service.  Added
#       search for facter objects in all of the modules which have 
#       command lines matching the pattern.
#  2013-07-24  Bill W. Added logic to follow additional includes found
#       inside a module's init.pp file.

require 'optparse'

#
# Variables
#

@MANIFEST_DIR = "/etc/puppet/manifests/nodes"
@MODULE_DIR = "/etc/puppet/modules"
@read_input = false
@SUDOERS = Hash.new
sudo_entry = Array.new
@manifest = Array.new
@provider = Array.new
@COMMANDS = Array.new
@debug = false


# echo is whitelisted because the sudo_file type uses it to get content into 
# files.  It should be innocent enough by itself to run as root as files targetted 
# in a redirect must use a pipe and the tee command.  tee is explicitly defined 
# in the sudoers.
@WHITELIST = ["/usr/bin/echo"]

# ALWAYS blacklist sudo itself.  Otherwise you can use sudo to execute sudo
# and get access to all the privileged commands root can access.  Sudo is not
# fully qualified and should exclude it no matter the path.
@BLACKLIST = ["sudo"]

#
# Functions
#

def process_manifest(manifest)
  pup_file = File.open(manifest, "r")
  pup_file.each do |line|
    case line
      when /^\s+include/
        if line =~ /.+\:\:.+/
          # Ignore it
        else
          if manifest =~ /init\.pp$/
            # If we're in an init.pp file in a module then includes should
            # be local to the module.
            sub_manifest = line.split[1]
            @manifest << "#{@MODULE_DIR}/#{manifest.split("/")[-3, 1]}/manifests/#{sub_manifest}.pp"
          else
            # Add another file to the manifests array.
            @manifest << "#{@MODULE_DIR}/#{line.split[1]}/manifests/init.pp"
          end
        end
      when /^\s+#/
        # Ignore any amount of white space and a '#'
      when /^\s+sudo_/
        # New object, zero out our working variables
        @obj_hash = Hash.new

        @read_input = true
        # Determine the type of entry.
        @type = line.split[0]

        if @debug 
          puts "Found type:  #{@type}" 
        end

        # Pull out the "name" of the object, this could be an
        # array of names.
        name = line.split("{")[1].chomp!.tr("[]\" ", "").chop.split(",")

        # Clean out any extra white space in the entries.
        if name.class == "Array"
          name.each_with_index { |x,y| name[y] = x.strip! }
        end

        @obj_hash.store("name", name)

      when /\}/
        if @read_input == true
          # Store the entry
          if @SUDOERS.has_key?("#{@type}")
            @SUDOERS["#{@type}"] << @obj_hash
          else
            @SUDOERS["#{@type}"] = Array.new
            @SUDOERS["#{@type}"][0] = @obj_hash
          end
          @read_input = false
        end
        #@obj_hash = Hash.new
      else
        if @read_input == true
          # Take the lines and add them to our store.
          # Assume everything is in a key, value pair.
          key = line.split("=>")[0].strip!
          value = line.split("=>")[1].chop.tr("\"","").strip!.chomp(",")
          @obj_hash.store(key, value)
        end
    end
  end

end

def process_file(data)
  # Step one, find our commands from the provider module.
  module_cmnds = Array.new
  module_cmnds = find_commands("bwilcox-sudo_helpers", "sudo_file", @provider)
  
  if module_cmnds.nil?
    puts "ERROR:  No data returned from the provider, skipping processing."
  else
  
    #puts "Module_cmnds: #{module_cmnds.inspect}"
  
    # If name is an Array then we have multiple objects to deal with.
    # Break it up into separate objects and deal with them one at a time.
    #puts data["name"].class  
    if data["name"].class == Array
      data["name"].each do |n|
        # The chmod command wants a leading 0 in decimal notation
        # if there is nothing set for the sticky bit.  So sanitize our
        # data accordingly.
        data.each do |x,y|
          if x == "mode" && y.length < 4
            data["#{x}"] = "0#{y}"
          end
        end
        process_commands(module_cmnds, data, n)
      end
    end

  end
  
end

def process_service(data)
  # Step one, find our commands from the provider module.
  module_cmnds = Array.new
  module_cmnds = find_commands("bwilcox-sudo_helpers", "sudo_service", @provider)

  if module_cmnds.nil?
    puts "ERROR:  No data returned from the provider, skipping processing."
  else
    # If name is an Array then we have multiple objects to deal with.
    # Break it up into separate objects and deal with them one at a time.
    #puts data["name"].class  
    if data["name"].class == Array
      data["name"].each do |n|
        process_commands(module_cmnds, data, n)
      end
    end
  end
end

def process_package(data)
  # Step one, find our commands from the provider module.
  module_cmnds = Array.new
  module_cmnds = find_commands("bwilcox-sudo_helpers", "sudo_package", @provider)

  if module_cmnds.nil?
    puts "ERROR:  No data returned from the provider, skipping processing."
  else

    #puts "Module_cmnds: #{module_cmnds.inspect}"

    # If name is an Array then we have multiple objects to deal with.
    # Break it up into separate objects and deal with them one at a time.
    #puts data["name"].class  
    if data["name"].class == Array
      data["name"].each do |n|
        # The chmod command wants a leading 0 in decimal notation
        # if there is nothing set for the sticky bit.  So sanitize our
        # data accordingly.
        data.each do |x,y|
          if x == "mode" && y.length < 4
            data["#{x}"] = "0#{y}"
          end
        end
        process_commands(module_cmnds, data, n)
      end
    end

  end

end

def process_user(data)
  # This an attempt at NOT hard coding commands into this script, but
  # determining them from the module. Experiment with using "*" for any
  # attribute that we don't know.
  
  # Step one, find our commands from the provider module.
  module_cmnds = Array.new
  module_cmnds = find_commands("bwilcox-sudo_helpers", "sudo_user", @provider)

  if module_cmnds.nil?
    puts "ERROR:  No data returned from the provider, skipping processing."
  else

    #puts module_cmnds.inspect

    # If name is an Array then we have multiple objects to deal with.
    # Break it up into separate objects and deal with them one at a time.
  
    if data["name"].class == Array
      data["name"].each do |n|
        process_commands(module_cmnds, data, n)
      end
    end
  end
end

def find_commands(module_name, sudo_type, provider_type)
  # find_commands searches the specified module, sudo type and provider type
  # to come up with the list of commands to execute.  It expects to find lines 
  # beginning with '@@sudo_cmnd' to identify command lines.  So a line like the following
  # would be processed:
  #
  # @@sudo_cmnd[:passwd] = "/usr/bin/passwd #{resource[:name]}"
  #
  # All lines that match the prefix are found and added to an Array of command lines.

   
  
  results = Array.new
  if File.exists?("#{@MODULE_DIR}/#{module_name}/lib/puppet/provider/#{sudo_type}/#{provider_type}.rb")
    provider = File.open("#{@MODULE_DIR}/#{module_name}/lib/puppet/provider/#{sudo_type}/#{provider_type}.rb", "r")
    provider.each do |line|
      case line
        when /^\s+@@sudo_cmnd\[/
          # Found our command definitions, read them in till we have them all.
          results << line.split("=")[1].tr("\"", "").strip!
      end
    end
    provider.close
    return results
  else
    puts "ERROR:  The specified provider, #{@provider}, does not exist for #{sudo_type}."
  end
end

def process_commands(commands, data, name)
  # process_commands does the heavy lifting of substituting attributes into the
  # command lines to formulate the sudoers commands.  Any block that we can't
  # resolve we put in a '*'.
  #puts "Processing data:  #{data.inspect}"

  commands.each do |command|
    next_command = false
    #puts "Before: #{command}"
    new_command = "#{command}"
        
    # Loop through this till we've replaced all blocks that ruby 
    # might otherwise evaluate
    while new_command =~ /\#\{(.*?)\}/
      #puts "New Command:  #{new_command}"
      new_block = new_command.match(/\#\{(.*?)\}/)[0]
      #puts "Processing block:  #{new_block}"
      if new_block =~ /\#\{resource\[(.*?)\]\}/

        # Determine what the symbol is
        this_obj = new_block.split(":")[1].tr("]}", "")
        #puts "This object is:  #{this_obj}"
            if data["#{this_obj}"].nil?
              #puts "Data doesn't have this object type, skipping command."
              next_command = true
              break
            end

        # If this_obj is 'name' use the 'name' passed to this function.
        case 
          when this_obj == "name"
            new_command.sub!(/\#\{(.*?)\}/, name)
          when !data.has_key?(this_obj)
            new_command.sub!(/\#\{(.*?)\}/, "*")
          else
            #puts data.inspect
            #puts data["#{this_obj}"]
            new_command.sub!(/\#\{(.*?)\}/, data["#{this_obj}"])
        end
      else
        # if it's not a resource, then it's something else we don't know about.
        new_command.sub!(/\#\{(.*?)\}/, "*")
      end

      # if we caught the failure break out of this loop.
      if next_command
        next
      end
     
    end # End while

    # if we caught the failure break out of this loop.
    if next_command
      next
    end

    # Discovered that sudo doesn't like : or \ in a command line. This
    # check will escape these if necessary.
    new_command.gsub!(/([:\\])/, '\\\\\&')
    
    #puts "After:  #{new_command}"
    @COMMANDS << new_command
  end
end

def process_facts(module_dir)
  # This function looks for all of the facts and finds command
  # lines for the sudoers file.  Same rules apply as for providers, 
  # the command lines must start with '@@sudo_cmnd'.  The difference
  # is that we're not trying to match them with resources from a manifest.

  # First, find all the files that may have facts.
  files = Dir["#{module_dir}/**/facter/*.rb"]

  # Go through each file and look for commands to add.
  files.each do |f|
    puts "In #{f}"
    lines = File.open(f, 'r')
    lines.each do |line|
      case line
        when /^\s+@@sudo_cmnd\[/
          # Found our command definitions, read them in till we have them all.
          @COMMANDS << line.split("=")[1].tr("\"", "").strip!
      end
    end
  end  

  # 
end

#
# Main
#

OptionParser.new do |o|
  o.on('-f FILENAME', 'Path and file to the manifest to parse') { |f| @manifest << f }
  o.on('-p PROVIDER', 'Provider to parse for commands [aix]') { |p| @provider << p }
  o.on('-d', 'Debug output on/off') { @debug = true }
  o.on('-h') {puts o; exit}
  o.parse!
end

unless @manifest
  puts "You must specify a file."
  exit 1
end

unless @provider
  puts "You must specify a provider [aix]"
  exit 1
end

@manifest.each do |manifest|
  process_manifest(manifest)
end

# The following is used for debugging.  It tells me how many entries in the
# type hash and for each type how many entries in the object hash and what the 
# names of the objects are.
if @debug
  puts "*** #{@manifest.length} manifests found."
  puts @manifest.inspect
  puts "*** #{@SUDOERS.length} types in the hash."
  @SUDOERS.each do |x,y|
    puts "*** #{y.length} objects in the #{x} hash."
    y.each do |a,b|
      puts a.inspect
    end
  end
end

# Process our data and output lines for the sudoers file.
@SUDOERS.each do |type,tdata|
  case type
    when "sudo_file"
      tdata.each do |data|
        process_file(data)
      end
    when "sudo_service"
      tdata.each do |data|
        process_service(data)
      end
    when "sudo_package"
      tdata.each do |data|
        process_package(data)
      end
    when "sudo_user"
      tdata.each do |data|
        process_user(data)
      end
  end
end

# Now look for any facts which contain commands matching
# out pattern
process_facts(@MODULE_DIR)

# Process the commands through the whitelist.  Entries in the 
# white list will be reduced to "<command> *" instead of using
# a fully qualified command line.
@WHITELIST.each_index do |w|
  check = Regexp.new(@WHITELIST[w])
  @COMMANDS.each_index do |x|
    if @COMMANDS[x] =~ check
      @COMMANDS[x] = "#{@WHITELIST[w]}"
    end
  end
end

# Process the commands through the blacklist.  Entries matching the 
# black list will be removed completely.
@BLACKLIST.each_index do |b|
  check = Regexp.new(@BLACKLIST[b])
  @COMMANDS.each_index do |x|
    if @COMMANDS[x] =~ check
      @COMMANDS.delete_at(x)
    end
  end
end


# Go through the output and remove duplicate entries.
@COMMANDS = @COMMANDS.uniq

80.times{print "="}
print "\n"
puts "The following command lines should be added to a sudoers Cmnd_Alias"
puts "which allows the puppet user to execute them.  You may need to check"
puts "for duplicate entries, and you should check for suitability."
80.times{print "="}
print "\n"
print "\t\t"
puts @COMMANDS.join(", \\\n\t\t")
