#bwilcox-sudo_helpers

####Table of Contents
1. [Overview](#overview)
2. [Module Description](#module-description)
3. [Setup](#setup)
4. [Usage](#usage)
5. [Limitations](#limitations)
6. [sudo_check.rb_](#sudo_check)

##Overview<a id="overview"></a>
This module was originally designed for a proof of concept to 
demonstrate how puppet could be run as a non-privileged user and 
still be allowed access to privileged commands via sudo.  The original use 
case was for a non-systems admin team who wanted to run, control and administrate
using puppet.  Wide-spread use of root by non-admins is bad.

After the POC I was challenged to flesh it out and use it for real, so here it is.

My working environment is AIX, so the providers are AIX specific but additional
providers should be relatively easy to produce given time and resources.

##Module Description<a id="module-description"></a>
The goal of this module is to provide functional equivalents to the native
puppet types. This module doesn't simply "su" to root but tries to define 
specific command lines used to accomplish tasks.  The companion script included
with this modules will parse a specified manifest and create a list of 
command lines which can be used in a sudoers file.

***NOTE:***  This is not meant to be a replacement for common sense and good 
security practice!  Sudo allows you to do things as a privileged user which
means you can still allow puppet, as a non-privileged user, to do things 
which could conceivably damage your system!

Some Types and parameters were implemented which do not
exist natively in puppet.  I found scenarios in which the extra parameters
were useful.  The types implemented do not have all of the
same parameters as the native Puppet equivalents.  In some cases 
this is because I don't have an immediate need for them, in other cases
a conscious decision was made to leave them out.  Recursing directory structures
is a good example of a parameter left out by design.  The goal of using sudo
is to have a more fine grained control over what puppet is allowed do.  If we allow
it to recursively change entire directory trees we're not really providing
any extra security.

Also included is a script, sudo_check.rb,  used to parse a given manifest and
create command lines which can be added to a sudo configuration.

***NOTE:*** Interesting behavior noted.  The sudo_helper_functions.rb file is 
included in the providers.  It holds code common to the providers.  If the puppet
master is restarted, agents will not 'see' this library until it's been modified. 
Opening the file and writing it causes puppet to see it again.  This fun little 
bug has resulted in me falling back to putting common functions in each file. 
Multiple copies of the same code, yay!

##Setup<a id="setup"></a>

Add this to your puppet installations modules directory and sync your agents.

Using this module, for the most part, should be as easy as replacing the puppet
types in your manifests with the equivalent "sudo_" types.  Naturally it also
requires sudo in your environment and a corresponding valid entires in the sudoers
file.

##Usage<a id="useage"></a>

####sudo_file
This type replicates file manipulation using sudo.

Valid parameters are:

* name - The file or directory name.
* mode - The permissions of the target, can be specified as decimal or ascii.
* owner - The login ID of the owner.
* group - The group id.
* replace - If the target exits as a different type than specified, whether or not to replace it (true/false).
* type - Must be one of directory, file, link.
* target - The target of a link. Required in order to create the link.
* content - A string describing the contents of a file.
* source - A URL/URI describing where to download the source file.
* provider - The provider for controlling this class. (Currently only AIX)

####sudo_package
This type replicates package management using sudo.

* name - The name short name of the package, ie. "httpd".
* install_pkg - The full name of the install file.
* pkg_type - The type of packages, either rpm or bff. Required for AIX to determine which commands to use to validate if a package is installed.
* source - The directory path to the install file.
* source_svr - The remote server hosting the file repository
* mount - If the package resides on a remote file system, pass the source to the mount command.  Unmounts on complettion.
* mount_point - The local mount point for remote directories. Required if you are mounting a remote repository.

####sudo_service
This type replicates service management using sudo.

* name - The name of the init script or service.
* path - Path to the init script.
* start - Command to start the service.
* stop - Command to stop the service.
* restart - Command to restart the service.
* status - Command to verify the service. Must return 0 for up.

####sudo_user
This type replicates user management using sudo.

* name - The login of the user.
* attributes - all the attributes that can be set in AIX that we don't have a specific manifest attribute for. This is an array of attribute=value pairs.
* comment - GECOS for the user.
* forcelocal - Force a local account even if the account is found in a directory service.
* gid - Primary group of the user.
* groups - Group set for the user.
* home - Home directory for the user.
* password - Hashed password for the user.
* shell - Shell for the user.
* uid - UID for the user."
* reqdir - Require the user to have an entry in an AD/LDAP directory. (true/false)

##Limitations<a id="limitations"></a>
Do not assume that just because you're doing something with sudo that your
commands are safe.  You still need to validate that entries you put into the
sudoers file do not expose your system to more risk than is necessary.

##Sudo_check.rb<a id="sudo_check"></a>
Currently the sudo_check.rb script provides command lines for 
every possible action a type could have on the named object, not just the 
actions described by the manifest.  sudo_check.rb is not aware of hiera.

Sudo_check's job is to spit out command lines, not determine if they are
reasonable, sane or even accurate.

For sudo check to work it's magic, the providers must have an easy
way to pull out the command lines being used.  This is done using
a Global Hash, ```@@sudo_cmnds``` which contains all of the command lines
used.  Some of these command lines are listed at the top of the provider while 
others may be interspersed throughout the provider.

Sudo_check examines every sudo type called by a manifest and looks for 
lines starting with "@@sudo_check." It treats all such lines as entries 
into the sudo_cmd hash.

If sudo_check cannot determine what to replace a variable with it will use
an "*" which may not be desired result!

It also contains both a white list and a black list for commands.  Commands entered
in the whitelist are assumed to be innocuous enough to not need parameters specified.
By default "echo" is considered one of these commands.

The black list will exclude any command line which matches an entry in the black
list.  The list by default contains "sudo" as we don't want sudo to be executed 
by root which would then allow any command to be run as root.

License
-------
Copyright 2013 Bill Wilcox

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Contact
-------

Initial design:  Bill Wilcox  bwilcox@4ied.net

Support
-------

Please log tickets and issues at [Projects site]https://github.com/bwilcox/bwilcox-sudo_helpers
