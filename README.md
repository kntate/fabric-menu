fusedeploy
===========

Fuse Fabric menu bash scripts used for managing JBoss Fuse environment for CenturyLink.

Initial Setup
-----------

There are several configuration files that define how the script work. Below is a description of each file.

######global-fuse-install.properties

File that contains global properties that are set for any user that runs the script.

######fuse-applications.properties

File that contains the list of applications that are available to each user. Each line is a property where the left side is application and right side is space delimited list of profiles assigned to the application. The list can also be modified using the add or edit applications in the bash menu script.

######<user>-fuse-install.properties

File that contains user specific properties, where '<user>' is the os user running the script. For example, meatlk-fuse-install.properties is the properties file for the meatlk user.

Connecting to Fuse
-----------

Start the menu by running scripts/fuse-menu.sh and make appropriate selections.
