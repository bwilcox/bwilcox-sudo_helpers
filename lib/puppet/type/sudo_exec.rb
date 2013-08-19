Puppet::Type.newtype(:sudo_exec) do
  @doc =  "POC use sudo to manage exec."

  # Set the provider, based on facter operatingsystem
  case :operatingsysem
    when "AIX"
      resource[:provider] = :aix
  end

  newparam(:command) do
    desc "The command line to exec."
    isnamevar
  end

  newparam(:creates) do
    desc "Command will only run if this file does not exist."
  end

  newparam(:cwd) do
    desc "Change to this working directory to execute."
  end

  newparam(:logoutput) do
    desc "Whether to log output.  Default is on_failure.  Valid values are true, false, on_failure"
    defaultto "on_failure"
  end

  newparam(:onlyif) do
    desc "Command will only run if this command executes and returns 0"
  end

end

