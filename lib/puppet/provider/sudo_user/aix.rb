# Explicitly call out the directory where the library is to deal with a known issue
# in how puppet resolves directories.  From what I've read this is addressed in
# the 3.0 release... maybe.
#require "/home/puppet/.puppet/var/lib/sudo_helper_functions.rb"
#include SudoFunctions


Puppet::Type.type(:sudo_user).provide(:aix) do
  desc "Provides support for managing users via sudo in AIX."

  # Declare the class variable here so it's available to all
  # parts of this module.
  @@sudo_cmnd = Hash.new

  def sudo_cmnds

    # Define the common command lines used in this provider here.
    # Only add here things that have no other variables, or only
    # puppet variables.  Otherwise the module will fail to load.
    # Other sudo_cmnd items should be declared before they are used
    # in relevant parts of the module. This will allow the script 
    # that generates the sudoers output to find the commands.

    @@sudo_cmnd[:lsuser_ldap] = "/usr/sbin/lsuser -R LDAP #{resource[:name]}"
    @@sudo_cmnd[:lsuser_files] = "/usr/sbin/lsuser -R files #{resource[:name]}"
    @@sudo_cmnd[:echo] = "/usr/bin/echo #{resource[:name]}:#{resource[:password]}" 
    @@sudo_cmnd[:chpasswd] = "/usr/bin/chpasswd -ec"
    @@sudo_cmnd[:rmuser_files] = "/usr/sbin/rmuser -R files -p #{resource[:name]}"
    @@sudo_cmnd[:grep_p] = "/usr/bin/grep -p #{resource[:name]} /etc/security/passwd"
    @@sudo_cmnd[:grep] = "/usr/bin/grep"
    @@sudo_cmnd[:awk] = "/usr/bin/awk"
    @@sudo_cmnd[:sudo] = "/usr/bin/sudo"


  end

  def create
    # We should be here if the local account exists, but doesn't 
    # match attributes in the manifest.  Or if the local account doesn't
    # exist and we need to create it.  Check for a coinciding 
    # LDAP account and make it match unless values are 
    # overridden in the manifest
    
    dresult = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:lsuser_ldap])
    lresult = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:lsuser_files])

    manifest_attributes = create_attr_hash(resource.to_hash)
    #puts manifest_attributes.inspect

    case
      when lresult[:rc] == 0
        # If we get here, we need to use the chguser command.
        # puts "local account for #{resource[:name]} exists, modify to match manifest."
        # Remove uid from the command line for changing accounts.  
        manifest_attributes.delete(:id)
        @@sudo_cmnd[:chuser_files] = "/usr/bin/chuser -R files #{make_attr_string(manifest_attributes)} #{resource[:name]}"
        command = @@sudo_cmnd[:chuser_files]
        #puts command
      when lresult[:rc] != 0 && dresult[:rc] == 0
        # If we get here, we need to merge the AD account with the manifest.
        #puts "local account for #{resource[:name]} doesn't exist, but AD entry does."
        dir_attrs = user_attr(dresult[:stdout])
        # Take out the login_id attribute as it's a construct of this process and not
        # an actual attribute in AIX.
        dir_attrs.delete(:login_id)
        manifest_attributes.each do |x,y|
          dir_attrs[x.to_sym] = y
        end
        
        @@sudo_cmnd[:mkuser_files_dir] = "/usr/bin/mkuser -R files #{make_attr_string(dir_attrs)} #{resource[:name]}"
        command = @@sudo_cmnd[:mkuser_files_dir]
        #puts command
      when lresult[:rc] != 0 && dresult[:rc] != 0
        # If we get here, make the account based on the manifest and let AIX
        # default for all non-specified attributes.
        #puts "local account for #{resource[:name]} doesn't exist, neither does an AD entry."
        @@sudo_cmnd[:mkuser_files] = "/usr/bin/mkuser -R files #{make_attr_string(manifest_attributes)} #{resource[:name]}"
        command = @@sudo_cmnd[:mkuser_files]
        #puts command
    end
    
    #puts command
    result = sudo_exec(@@sudo_cmnd[:sudo], command)  
    unless result[:rc] == 0
      fail "ERROR creating/modifying #{resource[:name]}"
      puts result[:stdout]
    end

    # if there is a password hash specified, set it for the user.
    if resource[:password]
      command = "#{@@sudo_cmnd[:echo]} | #{@@sudo_cmnd[:chpasswd]}"
      #puts command
      result = sudo_exec(@@sudo_cmnd[:sudo], command)
      unless result[:rc] == 0
        fail "ERROR setting password for #{resource[:name]}"
        puts result[:stdout]
      end
    end

  end

  def destroy

    # We should only destroy local accounts.  LDAP accounts should be managed 
    # from the directory side. I'm not destroying home directories by default.
    # If a user home directory should be removed/rename/re-permissioned use the
    # file type to do it.
    result = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:rmuser_files])

    unless result[:rc] == 0
      fail "ERROR creating/modifying #{resource[:name]}"
      puts result[:stdout]
    end

  end

  def exists?
    dresult = Hash.new
    lresult = Hash.new
  
    # Call the sudo_cmnds class to intialize the command lines with variables.
    sudo_cmnds

    # Normally all accounts should be in a directory.  Simply verify that
    # they exist there with specified values.  Error if the vales are different.
    # If the forcelocal attribute is set, then we create a local entry for the user
    # which matches the EXISTING LDAP ENTRY.  There MUST ALWAYS be an LDAP entry!
    dresult = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:lsuser_ldap])
    #puts "Directory:  #{dresult.inspect}"
    lresult = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:lsuser_files])
    #puts "Files: #{lresult.inspect}"

    if resource[:reqdir] == true
      if dresult[:rc] != 0
        # Fail if the account must be in the directory as we don't
        # have the authority to add users to the directory.
        fail "#{resource[:name]} is not in LDAP."
      end
    end
    
    if resource[:forcelocal] == true
      case
        when lresult[:rc] == 0 && resource[:ensure] == "present".to_sym
          # If the entry exists, compare the contents with what's in the manifest.
          # Return false unless everything matches.
          attr = Hash.new
          attr = user_attr(lresult[:stdout])

          # put together the attributes from the manifest and compare them with the 
          # user entry from the system.  If the manifest is different we have work
          # to do
          manifest_attributes = create_attr_hash(resource.to_hash)

          #puts "Manifest attributes: #{manifest_attributes.inspect}"
        
          # Compare the manifest attributes to the user attributes
          manifest_attributes.each do |name,value|
            # If just one of the attributes doesn't match, then 
            # fail so we can run the create method.
            unless attr[name.to_sym] == value
              puts "#{name} does not match for #{resource[:name]}."
              return false
            end
          end

          # Check the password hash, if it's different than the manifest
          # we need to update it
          if resource[:password] && resource[:ensure] == "present".to_sym
            command = "#{@@sudo_cmnd[:grep_p]} | #{@@sudo_cmnd[:grep]} password | #{@@sudo_cmnd[:awk]} '{print $3}'"
            #puts command
            result = sudo_exec(@@sudo_cmnd[:sudo], command)
            if result[:rc] == 0
              #puts "#{result[:stdout].strip!}  #{resource[:password]}"
              if result[:stdout].strip! != resource[:password]
                puts "Password is #{result[:stdout].strip!} and should be  #{resource[:password]}"
                return false
              end
            else
              fail "Unable to determine existing password hash for #{resource[:name]}."
            end
          end


        when lresult[:rc] == 0 && resource[:ensure] == "absent".to_sym
          return true
        when lresult[:rc] != 0 && resource[:ensure] == "present".to_sym
          return false
        when lresult[:rc] != 0 && resource[:ensure] == "absent".to_sym
          return false
      end
    end
    return true

  end

  #
  # Explicit functions
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

