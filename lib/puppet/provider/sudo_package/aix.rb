# Explicitly call out the directory where the library is to deal with a known issue
# in how puppet resolves directories.  From what I've read this is addressed in
# the 3.0 release... maybe.
#require "/home/puppet/.puppet/var/lib/sudo_helper_functions.rb"
#include SudoFunctions

Puppet::Type.type(:sudo_package).provide(:aix) do
  desc "Provides support for installing rpm's via sudo in AIX."

  confine :operatingsystem => [:aix]


  @@sudo_cmnd = Hash.new

  def sudo_cmnds
    @@sudo_cmnd[:sudo] = "/usr/bin/sudo"
    @@sudo_cmnd[:rpm_qa] = "/usr/bin/rpm -qa"
    @@sudo_cmnd[:grep] = "/usr/bin/grep  #{resource[:name]}"
    @@sudo_cmnd[:lpp_grep] = "/usr/bin/grep  #{resource[:install_pkg]}"
    @@sudo_cmnd[:mount] = "/usr/sbin/mount"
    @@sudo_cmnd[:lslpp] = "/usr/bin/lslpp -l"
  end

  def create

    # Mount the source if necesssary.
    if resource[:mount]

      # Make the mount point if it does not exist already.
      unless File.directory?(resource[:mount_point])
        @@sudo_cmnd[:mkdir] = "/usr/bin/mkdir #{resource[:mount_point]}"
        sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:mkdir] )
      end


      if resource[:source_svr]
        @@sudo_cmnd[:mount_cmnd] = "/usr/sbin/mount #{resource[:source_svr]}:#{resource[:source]} #{resource[:mount_point]}"
      else
        @@sudo_cmnd[:mount_cmnd] = "/usr/sbin/mount #{resource[:source_svr]}"
      end

      mnt_result = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:mount_cmnd])
      unless mnt_result[:rc] == 0
        fail "Unable to mount #{resource[:source]}."
      end
      #puts "mounted #{resource[:source]}"
    end

    # Perform the installation
    @@sudo_cmnd[:pkg_u] = "/usr/sbin/geninstall -I acgq -Y -d #{resource[:mount_point]} #{resource[:install_pkg]}"
    result = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:pkg_u])
    unless result[:rc] == 0
      fail "Failed to install package #{resource[:install_pkg]}"
    end

   # Unmount the source if necessary
   if resource[:mount]
     if resource[:source_svr]
       @@sudo_cmnd[:umount_cmnd] = "/usr/sbin/umount #{resource[:mount_point]}"
     else
       @@sudo_cmnd[:umount_cmnd] = "/usr/sbin/umount #{resource[:source]}"
     end
     umnt_result = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:mount_cmnd])
     unless umnt_result[:rc] == 0
       fail "Unable to unmount #{resource[:source]}."
     end
     #puts "unmounted #{resource[:source]}"
   end

  end

  def destroy
    # Determine the name we need to use
    case resource[:pkg_type] 
      when "rpm"
        pkg_result = sudo_exec(@@sudo_cmnd[:sudo], "#{@@sudo_cmnd[:rpm_qa]} | #{@@sudo_cmnd[:grep]}")
        @@sudo_cmnd[:pkg_e] = "/usr/sbin/geninstall -u #{pkg_result[:stdout]}"
      else
        @@sudo_cmnd[:pkg_e] = "/usr/sbin/geninstall -u -I g #{resource[:install_pkg]}"
    end

    result = sudo_exec(@@sudo_cmnd[:sudo], @@sudo_cmnd[:pkg_e])
    unless result[:rc] == 0
      notice "Darn it, couldn't remove #{resource[:name]}!"
    end
  end

  def exists?

    sudo_cmnds

    # How to tell if it's installed
    case resource[:pkg_type]
      when "rpm"
        result = sudo_exec(@@sudo_cmnd[:sudo], "#{@@sudo_cmnd[:rpm_qa]} | #{@@sudo_cmnd[:grep]}")
      else
        result = sudo_exec(@@sudo_cmnd[:sudo], "#{@@sudo_cmnd[:lslpp]} | #{@@sudo_cmnd[:lpp_grep]}") 
    end

    if result[:rc] == 0
      #notice "#{resource[:name]} is installed."
      return true
    else
      #notice "#{resource[:name]} is MISSING."
      return false
    end
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


end
