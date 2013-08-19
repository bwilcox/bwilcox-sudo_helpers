Puppet::Type.newtype(:sudo_package) do
  @doc =  "POC use sudo to install rpm's."

  ensurable

  newparam(:name) do
    desc "The short name."
    isnamevar
  end

  newparam(:install_pkg) do
    desc "The full name of the install file."
  end

  newparam(:pkg_type) do
    desc "The type of packages, either rpm or bff."
    defaultto "bff"
  end

  newparam(:source) do
    desc "The directory path to the file."
  end

  newparam(:source_svr) do
    desc "The remote server hosting the file repository"
  end

  newparam(:mount) do
    desc "If the package resides on a remote file system, pass the source to the mount command.  Unmounts on complettion."
    defaultto false
  end

  newparam(:mount_point) do
    desc "The local mount point for remote directories."
  end

end

