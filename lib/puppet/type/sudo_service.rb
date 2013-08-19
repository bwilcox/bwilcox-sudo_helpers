Puppet::Type.newtype(:sudo_service) do
  @doc =  "POC use sudo to manage services."

  ensurable

  # Set the provider, based on facter operatingsystem
  case :operatingsysem
    when "AIX"
      resource[:provider] = :aix
  end

  newparam(:name) do
    desc "The name of the init script."
    isnamevar
  end

  newparam(:path) do
    desc "Path to the init script."
  end

  newparam(:start) do
    desc "Command to start the service."
  end

  newparam(:stop) do
    desc "Command to stop the service."
  end

  newparam(:restart) do
    desc "Command to restart the service."
  end

  newparam(:status) do
    desc "Command to verify the service. Must return 0 for up."
  end

end

