# These are functions which may or may not be used by the various
# parts of the sudo_helper module.  Generally, if different providers
# need to do the same thing, put it in here. Write once, reuse.
# Try to keep command lines out of this library.  They should be
# specified in the appropriate provider.
#
# This isn't actually used as there is an issue in puppet where
# it doesn't read in libraries as expected.  Maybe fixed in 
# version 3.  
 
module SudoFunctions
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

  def user_attr(stdout)
    # Take the output of lsuser and put it into a hash to make 
    # comparisons with manifest entries easier.
    user_hash = Hash.new
    attr = stdout.split()

    # The first element in the output is the login ID.
    user_hash[:login_id] = attr[0]

    # For the rest of the hash, separate the output into key/value
    # pairs.  Add some logic to put the GECOS field back together.
    attr[1..-1].each do |a|
      case a
        when /^\w+=/
          user_hash[a.split("=")[0].to_sym] = a.split("=")[1]
        else
          # try to detect items from the GECO field and add them back together
          user_hash[:gecos] = user_hash[:gecos] + " " +a
      end
    end
    return user_hash
  end

  def create_attr_hash(items)
    # This takes the puppet resource variable and converts it to 
    # a proper hash so we can more easily compare what a user
    # manifest specifies with what actually exists.
    result = Hash.new
    items.each do |name,value|
      case name.to_s
        when "attributes"
          value.each do |record|
            result[record.chomp("\"").split("=")[0].to_sym] = record.chomp("\"").split("=")[1]
          end
        when "comment"
          result[:gecos] = value
        when "gid"
          result[:pgrp] = value
        when "groups"
          result[:groups] = value
        when "home"
          result[:home] = value
        when "shell"
          result[:shell] = value
        when "uid"
          result[:id] = value
      end
    end
    return result
  end

  def make_attr_string(attrs)
    # This takes the hash of user attributes, usually created with create_attr_hash
    # and flattens it to a string for inclusion in a mkuser or chuser command line.
    result = Array.new
    attrs.each do |x,y|
      result << "#{x}='#{y}'"
    end
    return result.join(" ")
  end
end
