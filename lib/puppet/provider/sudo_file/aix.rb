# Explicitly call out the directory where the library is to deal with a known issue
# in how puppet resolves directories.  From what I've read this is addressed in
# the 3.0 release... maybe.
#require "sudo_helper_functions.rb"
#include SudoFunctions

Puppet::Type.type(:sudo_file).provide(:aix) do
  desc "Provides support for managing files via sudo in AIX."

  confine :operatingsystem => [:aix]

  @@sudo_cmnd = Hash.new

  def sudo_cmnds
    @@sudo_cmnd[:sudo] = "/usr/bin/sudo"
    @@sudo_cmnd[:ls_l] = "/usr/bin/ls -ld #{resource[:name]}"
    @@sudo_cmnd[:mkdir] = "/usr/bin/mkdir #{resource[:name]}"
    @@sudo_cmnd[:touch] = "/usr/bin/touch #{resource[:name]}"
    @@sudo_cmnd[:file] = "/usr/bin/file -i #{resource[:name]}"
    @@sudo_cmnd[:rm] = "/usr/bin/rm -rf #{resource[:name]}"
  end

  def create
    # puts "Create: #{resource[:name]}"

    # Verify and fix 
    output = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:ls_l])
    #puts "Target owner/group:  #{resource[:owner]}:#{resource[:group]}"
    #puts output.inspect
    if output[:rc] != 0
      # If the file doesn't exist we need to have type, owner and group defined in the manifest.
      unless resource[:type] && resource[:owner] && resource[:group]
        fail "Must have type, owner and group to create the resource!" 
      end

      # Create the target
      case resource[:type]
        when "directory"
          sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:mkdir])
        when "file"
          sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:touch])
        when "link"
          # If type is a link, must also have the target parameter.
          if resource[:target]
            @@sudo_cmnd[:ln] = "/usr/bin/ln -sf #{resource[:target]} #{resource[:name]}"
            sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:ln])
          else
            fail "Must set resource 'target' to generate a link."
          end    
        else
          fail "Not sure what to do with type of #{resource[:type]}."
      end

      # Now that the file exists, reload the output hash.
      output = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:ls_l])

    end

    # Check if the type is changing.  If it is throw an error.
    # Changing types could be destructive.
    unless resource[:type].nil?
      this_type = get_type(sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:file])[:stdout])
      if this_type != resource[:type]
        fail "ERROR:  Type change of exiting resource #{resource[:name]} from '#{this_type}' to '#{resource[:type]}'"
      end
    end

    # If we're making a link, ignore setting owner and permissions
    unless this_type == "link"

      # If a source has been defined, copy it first.
      unless resource[:source].nil?
        @@sudo_cmnd[:cp] = "/usr/bin/cp #{resource[:source]} #{resource[:name]}"
        sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:cp])
      end

      # Set owner and permissions
      # Verify owner/group and only change if we have to
      unless resource[:owner].nil?
      unless output[:stdout].split[2] == resource[:owner] && output[:stdout].split[3] == resource[:group]
        #puts "Target owner/group:  #{resource[:owner]}:#{resource[:group]}"
        @@sudo_cmnd[:chown] = "/usr/bin/chown #{resource[:owner]}:#{resource[:group]} #{resource[:name]}"
        sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:chown])
      end
      end

      # Verify mode and only change if we have to.
      # First we take the permissions and convert it to decimal.
      perms = output[:stdout].split[0]
      mode_decimal = mode_convert(perms)

      #puts mode_decimal
      #puts "Actual: #{mode_decimal}"
      #puts "Desired: #{resource[:mode]}"
 
      unless resource[:mode].nil? || mode_decimal == resource[:mode]
        @@sudo_cmnd[:chmod] = "/usr/bin/chmod #{resource[:mode]} #{resource[:name]}"
        sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:chmod])
      end
    end

    # If there is content to put in, put it in.
    unless resource[:content].nil?
      @@sudo_cmnd[:echo] = "/usr/bin/echo '#{resource[:content]}'"
      @@sudo_cmnd[:tee] = "/usr/bin/tee  #{resource[:name]}"
      sudo_exec(@@sudo_cmnd[:sudo], "#{@@sudo_cmnd[:echo]} | #{@@sudo_cmnd[:tee]}")
    end

  end

  def destroy
    #puts "Destroy: #{resource[:name]}"
    # Really dangerous stuff here...
    # Try to prevent some really stupid stuff if we can
    protected = ["/", "/usr", "/sbin", "/bin", "/var", "/etc", "/etc/security", "/etc/security/user", "/etc/security/passwd"]
    protected.each do |p|
      if p.eql?(resource[:name])
        fail "ID=10T Error Avoided!"
      end
    end
    sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:rm])
  end

  def exists?

    sudo_cmnds

    #puts "Exists? #{resource[:name]}"

    # Check for the mode resource, if it's here see if it has the sticky bit position.
    # if not, add it and set the value to 0.  The create method wants to see that position
    # even if it's 0.
    if resource[:mode] && resource[:mode].length < 4
      resource[:mode] = "0#{resource[:mode]}"
    end

    # How to tell if it's installed
    # Pull information on the file.
    output = Hash.new()
    output = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:ls_l])
    #puts resource[:name]
    #puts output.inspect
    case output[:rc]
      when 0
        #puts "in 0"
        #puts "#{resource[:name]} is present."
        #puts resource[:content] 
        #puts "Ensure = #{resource[:ensure]}"

        # If the file exists and ensure is set to absent, 
        # return true to trigger the destroy method.
        if resource[:ensure] == :absent
          return true
        end
 
        # Get the attributes of the file
        perms = output[:stdout].split[0]
        #notice "Perms are:  #{perms}."
        owner = output[:stdout].split[2]
        #notice "Owner is:  #{owner}."
        group = output[:stdout].split[3]
        #notice "Group is:  #{group}."

        file_output = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:file])
        type = get_type(file_output[:stdout])

        #notice "Type is:  #{type}."

        # If the type is link, ignore owner and permissions
        unless type == "link"
          #puts "not a link"
          unless resource[:owner].nil? || owner.eql?(resource[:owner])
            notice "#{resource[:name]} owned by #{owner} and should be #{resource[:owner]}"
            return false
          end

          unless resource[:group].nil? || group.eql?(resource[:group])
            notice "#{resource[:name]} owned by #{group} and should be #{resource[:group]}"
            return false
          end

          # Verify mode
          # First we take the permissions and convert it to decimal.
          mode_decimal = mode_convert(perms)

          # If the resource mode is given in symbolic notation, figure out 
          # what the final mode should be and use that to compare with what
          # we have.
          if resource[:mode] && resource[:mode] =~ /^[ugoa]/
            desired_mode = convert_mode(resource[:mode], mode_decimal)
          else
            desired_mode = resource[:mode]
          end

          unless resource[:mode].nil? || mode_decimal == desired_mode
            notice "#{resource[:name]} has mode #{mode_decimal} and should be #{desired_mode}"
            return false
          end

          # Verify the contents of the file
          #puts "Verifying contents..."
          case 
            when resource[:source] && resource[:ensure] == :present
              #puts "In case with source and present."
              # This should be the file copied using puppet's built in file type 
              # to a location that the puppet user can access.  Compare that file to
              # ours and make sure they are the same.
              @@sudo_cmnd[:cksum_src] = "/usr/bin/cksum  #{resource[:source]}"
              @@sudo_cmnd[:cksum] = "/usr/bin/cksum  #{resource[:name]}"
              src_sum = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:cksum_src])
              tgt_sum = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:cksum])
              unless src_sum[:stdout].split[0] == tgt_sum[:stdout].split[0]
                return false
              end
            when !resource[:content].nil?
              #puts "In case with content and present."
              # Read the contents of the file and compare it to what we have.
              @@sudo_cmnd[:cat] = "/usr/bin/cat #{resource[:name]}"
              result = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:cat])[:stdout].chop
              unless resource[:content] == result
                notice "#{resource[:name]} has content '#{result}' and should be '#{resource[:content]}'"
                return false
              end
          end

        end
        #puts "I think that was a link."

        unless resource[:type].nil? || type.eql?(resource[:type])
          fail "#{resource[:name]} has type '#{type}' and should be '#{resource[:type]}'"
        end

        return true
      when 2
        #puts "in 2"
        unless resource[:ensure] == :absent
          notice "#{resource[:name]} is MISSING."
          return false
        end
      else
        notice "'#{command}' failed."
        exit
    end

  end

  # 
  # Explicit functions, sorry for duplicates.  Can't be helped at this time.
  #

  def sudo_exec(sudo, command)
    # Execute the given command using sudo and return a hash with 
    # stdout and rc results.
    # If there is a pipe, add sudo after it so the subsequent command is
    # also sudo sanitized.
    #puts "Command to expand:  #{command}"
    #cmd_line = "/usr/bin/sudo #{command.gsub(/\|/, ' | /usr/bin/sudo ')}"
    pipe_sub = " | #{sudo} "
    cmd_line = "#{sudo} #{command.gsub(/\|/, pipe_sub)}"
    #puts "Command to exec:  #{cmd_line}"
    result = Hash.new
    result[:stdout] = `#{cmd_line} 2>/dev/null`
    result[:rc] = $?.exitstatus
    return result
  end

  def mode_convert(mode)
    # Convert permissions as shown in ls output to decimal notation.
    # Expects as input a string of three characters, each position is
    # one of '-', 'r', 'w', or 'x'.
    perms = Array.new

    #puts mode

    # Break things up a bit
    perms[0] = 0
    perms[1] = mode[1..3]
    perms[2] = mode[4..6]
    perms[3] = mode[7..9]

    #puts perms.inspect

    perms.each_with_index do |perm,x|
      # New variable for each run
      output = Array.new
      sticky = false

      unless x == 0
        # We don't evaluate the first position, that's the sticky bit position
        # and should only be 1 character in size.  Values should be 0, 2 or 4.

        perm.split("").each_with_index do |p,i|
          case p
            when "-"
              output[i] = "0"
            when "r"
              output[i] = "4"
            when "w"
              output[i] = "2"
            when "x"
              output[i] = "1"
            when "s"
              output[i] = "1"
              case x
                when 1
                  perms[0]+=4
                when 2
                  perms[0]+=2
              end
            else
              # Do nothing
          end
        end


        perms["#{x}".to_i] = output[0].to_i + output[1].to_i + output[2].to_i

        #puts perms.inspect

      end

    end

    # Add the members of the output array and return the result.
    return perms.join("")
  end

  def get_type (output)
    # Get the type of a file
    # Return one of file, link, directory
    #command = "#{sudo} /usr/bin/file -i #{file}"
    #output = `#{command}`
    #puts output
    case output.split(":")[1]
      when  /regular file/
        return "file"
      when  /symbolic link/
        return "link"
      when  /directory/
        return "directory"
      else
        notice "Could not determine type of #{resource[:name]}"
    end
  end

def convert_mode(mode, existing)
  # hash to hold values while we 'ca-ching-a-late'
  perms = Hash.new
  perms[:sticky] = 0
  perms[:user] = Array.new
  perms[:group] = Array.new
  perms[:other] = Array.new

  # Take the existing mode and pre-load the perms Hash with it.
  perms[:sticky] = num_to_array(existing[0,1].to_i)
  perms[:user] = num_to_array(existing[1,1].to_i)
  perms[:group] = num_to_array(existing[2,1].to_i)
  perms[:other] = num_to_array(existing[3,1].to_i)

  #puts "Preloaded perms:  #{perms.inspect}"

  # Input is a comma separated array.
  mode.split(",").each do |m|
    who = Array.new
    # Further split based on the operator so we can tell who
    test = m.split(/\=|\+|\-/)
    #puts test.inspect
    test[0].each_char do |x|
      #puts "Setting #{x}"
      case x
        when "u"
          who << :user
        when "g"
          who << :group
        when "o"
          who << :other
        when "a"
          who = [:user, :group, :other]
      end
    end

      case m
        when /=/
          #Exact or add permission set.
          who.each do |w|
            converted_perm = convert_perm(test[1])
            perms[w] = converted_perm
            if m =~ /t/
              perms[:sticky] = [1]
            end
           if m =~ /s/
              case w
                when :group
                  perms[:sticky] = [2]
                when :user
                  perms[:sticky] = [4]
              end
            end
          end
        when /\+/
          #Exact or add permission set.
          who.each do |w|
            converted_perm = convert_perm(test[1])
            converted_perm.each do |c|
              unless perms[w].include?(c)
                perms[w] << c
              end
            end
            if m =~ /t/
              unless perms[:sticky].include?(1)
                perms[:sticky] << 1
              end
            end
            if m =~ /s/
              case w
                when :group
                  unless perms[:sticky].include?(2)
                    perms[:sticky] << 2
                  end
                when :user
                  unless perms[:sticky].include?(4)
                    perms[:sticky] << 4
                  end
              end
            end
          end
        when /\-/
          # Remove permission from existing.
          who.each do |w|
            converted_perm = convert_perm(test[1])
            converted_perm.each do |c|
              if perms[w].include?(c)
                perms[w].delete(c)
              end
            end
            if m =~ /t/
              if perms[:sticky].include?(1)
                perms[:sticky].delete(1)
              end
            end
           if m =~ /s/
              case w
                when :group
                  if perms[:sticky].include?(1)
                    perms[:sticky].delete(2)
                  end
                when :user
                  unless perms[:sticky].include?(1)
                    perms[:sticky].delete(4)
                  end
              end
            end

          end
      end

  end

  #puts "Postloaded perms: #{perms.inspect}"
  # Put the permissions together and return the decimal notation

  return "#{add_array(perms[:sticky])}#{add_array(perms[:user])}#{add_array(perms[:group])}#{add_array(perms[:other])}"

end

def convert_perm(perm)
  # Take ascii represented permissions and turn them into decimals.
  #puts "Perm is #{perm}"
  total = 0
  result = Array.new
  perm.each_char do |p|
    case p
      when "r"
        unless result.include?(4)
          result << 4
        end
      when "w"
        unless result.include?(2)
          result << 2
        end
      when "x"
        unless result.include?(1)
          result << 1
        end
    end
  end

  #puts "Result before add: #{result.inspect}"

  # Add the values in the array and return the value
  return result

end

def add_array(stuff)
  # Add the values in the array and return the value
  total = 0
  stuff.each do |s|
    total += s.to_i
  end
  return total
end

def num_to_array(number)
  # Take a number representing permissions and
  # break it into an array.
  case number
    when 7
      return [2, 1, 4]
    when 6
      return [2, 4]
    when 5
      return [1, 4]
    when 4
      return [4]
    when 0
      return [0]
  end
end


end

