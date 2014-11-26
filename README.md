fusedeploy
===========

Fuse Fabric menu bash scripts used for managing JBoss Fuse environment for CenturyLink.

Initial Configuration
-----------

There are several configuration files that define how the script work. Below is a description of each file.

######properties/global-fuse-install.properties

File that contains global properties that are set for any user that runs the script.

######properties/fuse-applications.properties

File that contains the list of applications that are available to each user. Each line is a property where the left side is application and right side is space delimited list of profiles assigned to the application. The list can also be modified using the add or edit applications in the bash menu script.

######properties/[user]-fuse-install.properties

File that contains user specific properties, where '[user]' is the os user running the script. For example, meatlk-fuse-install.properties is the properties file for the meatlk user.

Connecting to Fuse
-----------

Connection info to the Fuse server is found in the [user]-fuse-install.properties file. If the following properties are not found in this file or if the Fuse connection cannot be created then the script will prompt for the connection details.

    ENSEMBLE_SERVER_HOST=vlmdcdfab100.dev.intranet
    ENSEMBLE_SERVER_USER=admin
    ENSEMBLE_SERVER_PASSWORD=admin
    ENSEMBLE_SERVER_PORT=8101

Creating the Fabric Instance
-----------

A Fuse server must be running and accessible for the script to startup; however a Fabric container does not need to be created. If the script senses that Fabric has not been created it will prompt the user if it should be created. If answered yes the script will run the fabric:create command against the Fuse Command Console. If answered no then the script will exit because Fabric creation is a pre-requisite.

Starting the Script
===========

Start the menu by running scripts/fuse-menu.sh and make appropriate selections.

Selecting the Application
-----------

The script will prompt the user for which application they want to administer. The list of applications is maintained in the fuse-applications.properties file. The user will be presented with a menu selection of all available applications as well as a "newApplication", "editApplication", and "removeApplication" options.

######newApplication

Option will prompt the user for the name of the application and what Fabric profile to use when creating a new instance of the application. The Fabric profile needs to already exist in the Fuse Fabric server instance. The script will add the application/profile to the fuse-applications.properties file so that it is available for all subsequent runs. 

######editApplication

Option will prompt the user with a select menu of the available applications. After choosing the application the user will be prompted for the Fabric profile to use for all new instances of the application. The script will edit the application/profile in the fuse-applications.properties file so that it is available for all subsequent runs. The profile will then be applied to all new instances of the application, however any previously existing instance must use the add/remove profile options to update the profile.

######removeApplication

Option will prompt the user with a select menu of the available applications. The script will remove the chosen application from the fuse-applications.properties file but any existing instances for that application will still remain in Fabric. If desired, use the removeInstance option before this option to ensure all instances are deleted.

Selecting the Environment
-----------

The script will prompt the user for which environment they want to administer. The list of environments is maintained by the available_environments property in the [user]-fuse-install.properties file. The user will be presented with a menu selection of all available environments as well as a "newEnvironment" and "removeEnvironment" options.

######newEnvironment

Option will prompt the user for the name of the enviornment to add. The script will edit the available_environments property in the [user]-fuse-install.properties file so that it is available for all subsequent runs. 

######removeEnvironment

Option will prompt the user with a select menu of the available environments. The script will remove the chosen application from the available_environments property in the [user]-fuse-install.properties file but any existing instances for that environment will still remain in Fabric. If desired, use the removeInstance option before this option to ensure all instances are deleted.

Using the Script
===========

Once it has been ensured that Fabric is created and Fuse is running and the user has selected the application/environment to administer, then the user will get the root menu of the script. This section will detail how to use the following options.

installInstance
-----------

Option used to install an instance of the application to the selected environment.

When installing an application instance the user has the option to either include the instance in the Zookeeper Registry Group or to keep the instance as a simple Fabric managed instance. It is recommended that the instance be a simple managed instance unless there is a driving reason for it to be in the Zookeeper Registry Group. The Zookeeper Registry Group is the set of containers that form the quorem for tracking Fabric configuration. Most instances should just be a simple managed instance.

The name of the instance will be in the format of [application]\_[enviornment]\_# where # is the next number in the sequence of instances or 1 if it is the first instance for the application in the given enviornment.

The user will be prompted for the hostname of the server to install each instance on. Fabric will then be used to install an instance container via ssh onto the selected host with the user running the script. Therefore, the Fabric server must have ssh keys setup to the selected host.

removeInstance
-----------

Option used to remove an instance (or all instances) of the given application in the selected enviornment. Will not only remove the instance from the Fabric Zookeeper Registry but will also delete all files on the server hosting the instance.

The user will be prompted with a select menu that includes all instances along with an all option.

Administration
-----------

Option that prompts the user with a new menu of adminstration tasks

######sshToInstanceUser

Option that allows the user to select an instance server to run a bash command against.
		  	
######instanceUpgrade

Option that allows a user to upgrade the instance container version on a selected instance or the entire set of instances in the selected application/enviornment. For upgrading a single instance the user will be prompted for all available versions more recent than the current version, however for upgrading all instance containers the user must enter the desired version.

######instanceRollback

Option that allows a user to rollback the instance container version on a selected instance or the entire set of instances in the selected application/enviornment. For rolling back a single instance the user will be prompted for all available versions older recent than the current version, however for upgrading all instance containers the user must enter the desired version.

######startInstance

Will start the Fuse process associated with the application instance. An all option is also included.

######stopInstance

Will stop the Fuse process associated with the application instance. An all option is also included.

######addProfile

Adds a Fabric profile to the selected instance.

######environmentInfo

Gives an overview of the instance containers for the application in the selected environment.

######removeProfile

Removes a Fabric profile to the selected instance.

######instanceStatus

Gives the status and instance overview of the selected instance or all instances in the enviornment.

######activeMQStats

Returns basic ActiveMQ stats for the selected container.

######threadDump

Will perform a thread dump of the Fuse Java process and write the output to the user supplied location.

######instanceConnect

Camel
-----------

######camelRouteStart

######camelRouteStop

######camelRouteInfo