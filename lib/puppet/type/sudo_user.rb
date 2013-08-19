Puppet::Type.newtype(:sudo_user) do
  @doc =  "POC use sudo to manage users."

  ensurable

  # Set the provider, based on facter operatingsystem
  #case :operatingsysem
  #  when "AIX"
  #    resource[:provider] = :aix
  #end

  newparam(:name) do
    desc "The login of the user."
    isnamevar
  end

  newparam(:attributes) do
    # this is for all the attributes that can be set in AIX 
    # that we don't have a specific manifest attribute for.
    desc "An array of attribute=value pairs."
  end

  newparam(:comment) do
    desc "GECOS for the user."
  end

  newparam(:forcelocal) do
    desc "Force a local account."
  end
  
  newparam(:gid) do
    desc "Primary group of the user."
  end

  newparam(:groups) do
    desc "Group set for the user."
  end

  newparam(:home) do
    desc "Home directory for the user."
  end

  newparam(:password) do
    desc "Hashed password for the user."
  end

  newparam(:shell) do
    desc "Shell for the user."
  end

  newparam(:uid) do
    desc "UID for the user."
  end

  newparam(:reqdir) do
    desc "Require the user to have an entry in an AD/LDAP directory."
    defaultto true
  end

end

