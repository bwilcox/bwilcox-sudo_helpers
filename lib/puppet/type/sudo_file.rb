Puppet::Type.newtype(:sudo_file) do
  @doc =  "POC use sudo to manage files."

  ensurable

  # Set the provider, based on facter operatingsystem
  case :operatingsysem
    when "AIX"
      resource[:provider] = :aix
  end

  newparam(:name) do
    desc "The file name."
    isnamevar
  end

  newparam(:mode) do
    desc "The decimal permissions of the target."
  end

  newparam(:owner) do
    desc "The login ID of the owner."
  end

  newparam(:group) do
    desc "The group id."
  end

  newparam(:replace) do
    desc ""
  end

  newparam(:type) do
    desc "Must be one of directory, file, link."
  end

  newparam(:target) do
    desc "The target of a link. Required in order to create the link."
  end

  newparam(:content) do
    desc "A string describing the contents of a file."
  end

  newparam(:source) do
    desc "A URL/URI describing where the source file."
  end

  newparam(:provider) do
    desc "The provider for controlling this class."
  end

end

