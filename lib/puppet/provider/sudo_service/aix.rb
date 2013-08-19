# Explicitly call out the directory where the library is to deal with a known issue
# in how puppet resolves directories.  From what I've read this is addressed in
# the 3.0 release... maybe.
#require "/home/puppet/.puppet/var/lib/sudo_helper_functions.rb"
#include SudoFunctions



Puppet::Type.type(:sudo_service).provide(:aix) do
  desc "Provides support for managing services via sudo in AIX."

  confine :operatingsystem => [:aix]

  @@sudo_cmnd = Hash.new

  def sudo_cmnds
    @@sudo_cmnd[:sudo] = "/usr/bin/sudo"
    @@sudo_cmnd[:startsrc] = "/usr/bin/startsrc -s #{resource[:name]}"
    @@sudo_cmnd[:stopsrc] = "/usr/bin/stopsrc -s #{resource[:name]}"
    @@sudo_cmnd[:refresh] = "/usr/bin/refresh -s #{resource[:name]}"
    @@sudo_cmnd[:lssrc] = "/usr/bin/lssrc -s #{resource[:name]}"
    @@sudo_cmnd[:rcstatus] = "#{resource[:path]} #{resource[:status]}"
    @@sudo_cmnd[:rcstart] = "#{resource[:path]} #{resource[:start]}"
    @@sudo_cmnd[:rcstop] = "#{resource[:path]} #{resource[:stop]}"
    @@sudo_cmnd[:rcexist] = "/usr/bin/ls -ld #{resource[:path]}"
  end

  def create
    if resource[:path]
      start_cmnd = @@sudo_cmnd[:rcstart]
    else
      start_cmnd = @@sudo_cmnd[:startsrc]
    end

    result = sudo_exec(@@sudo_cmnd[:sudo], start_cmnd)
    unless result[:rc] == 0
      fail "Unable to start service #{resource[:name]}."
    end
  end

  def destroy
    if resource[:path]
      stop_cmnd = @@sudo_cmnd[:rcstop]
    else
      stop_cmnd = @@sudo_cmnd[:stopsrc]
    end

    result = sudo_exec(@@sudo_cmnd[:sudo], stop_cmnd)
    unless result[:rc] == 0
      fail "Unable to stop service #{resource[:name]}."
    end
  end

  def exists?

    sudo_cmnds
   
    # If the path resource is set then this service is controlled by an
    # rc script.  If not, then use the system resource controller commands.
    if resource[:path]
      # Make sure the rc script is where we need it
      file_exists = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:rcexist])
      unless file_exists[:rc] == 0
        fail "Cannot find #{resource[:path]}"
      end

      status = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:rcstatus])
      if status[:rc] == 0
        return true
      else
        return false
      end
      
    else
      status = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:lssrc]) 
      case status[:stdout]
        when /active$/
          return true
        else
          return false
      end
    end

  end

  # 
  # Implicit functions
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



end

