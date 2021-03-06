#!/bin/bash 

if [ -z $FUSE_HOME ]; then
  FUSE_HOME=$fuse_home_default
fi
FUSE_BIN=$FUSE_HOME/bin
FUSE_CLIENT_SCRIPT_PATH=$FUSE_BIN/client
FUSE_USER=`whoami`

# Make sure the properties file exists
USER_PROPS_FILE="${PROPERTIES}/${FUSE_USER}-fuse-install.properties"
if [ ! -f "$USER_PROPS_FILE" ]; then
  echo "Error, user properties file not found at $USER_PROPS_FILE"
  echo "Create file and try again."
  exit 1
fi

# source the users properties file
. $USER_PROPS_FILE

ZIP_FILENAME="fabric8-karaf-1.0.0.redhat-379.zip"

hidden_password="******"

# Make sure client script exists
if [ ! -f "$FUSE_CLIENT_SCRIPT_PATH" ]; then
  echo "Error: Fuse client script does not exist at $FUSE_CLIENT_SCRIPT_PATH"
  echo "Either set FUSE_HOME or fix fuse_home_default"
  exit 1
fi

chooseApplication(){
  getApplicationList
  
  application_list+=('newApplication')
  application_list+=('editApplication')
  application_list+=('removeApplication')

  echo "Enter number of the desired application:"
  select chosen_application in "${application_list[@]}"
  do
    echo "Application chosen: $chosen_application"
    break
  done
  
  if [ -z "$chosen_application" ]; then
    echo "Invalid choice, try again."
    chooseApplication
  else
    if [ "$chosen_application" = "newApplication" ]; then
      addApplication
      chooseApplication
    elif [ "$chosen_application" = "editApplication" ]; then
      editApplication
      chooseApplication
    elif [ "$chosen_application" = "removeApplication" ]; then
      removeApplication
      chooseApplication      
    else
      getProfilesForApplication
    fi
  fi
       
}

removeApplication(){
  getApplicationList
  echo "Enter number of the desired application:"
  select chosen_application in "${application_list[@]}"
  do
    echo "Application chosen: $chosen_application"
    break
  done
  
  profiles=`egrep ^$chosen_application= $application_properties_file | cut -f2 -d"="`
  echo "Are you sure you want to remove application \"$chosen_application\" with the following profiles?"
  echo -e "\t${profiles}"
  echo "Enter [y:n]"
  
  read should_remove
  
  if [ "$should_remove" == "y" ]; then
    echo "Removing $chosen_application"
    sed -i "s/$chosen_application=$profiles//" $application_properties_file
  else
    echo "Not removing application"
  fi
}

editApplication(){
  getApplicationList
  echo "Enter number of the desired application:"
  select chosen_application in "${application_list[@]}"
  do
    echo "Application chosen: $chosen_application"
    break
  done

  profiles=`egrep ^$chosen_application= $application_properties_file | cut -f2 -d"="`
  echo "Current profiles for application \"$chosen_application\", profiles:"
  echo -e "\t${profiles}"

  echo "Enter new profiles for application:"
  read newProfiles

  sed -i "s/$chosen_application=$profiles/$chosen_application=$newProfiles/" $application_properties_file
}

addApplication(){
  default_profile="default"
  getApplicationList

  echo "Enter name of application:"
  read application_name
  
  # determine if the environment already exists
  application_exists="false"
  for i in "${application_list[@]}"
  do
    if [ "$i" == "$application_name" ]; then
      application_exists="true"
    fi
  done
  
  # only add the environment if it does not already exist
  if [ "$application_exists" == "true" ]; then
    echo "Error, application \"$application_name\" already exists. Please input a non-existent application."
    addApplication
  else
    echo "Enter profile for application $application_name:"
    echo "Default: $default_profile"
    read application_profile  
    application_profile=${application_profile:-$default_profile}
    
    echo "Creating application: \"$application_name\" with profiles: \"$application_profile\""
      
    echo "${application_name}=${application_profile}" >> $application_properties_file
  fi
}

getProfilesForApplication(){
  application=$1
  profiles=`egrep ^$chosen_application= $application_properties_file | cut -f2 -d"="`
  profile_list=( $profiles )
  managed_profile_args=""
  for profile in "${profile_list[@]}"
  do
    managed_profile_args="$managed_profile_args --profile $profile"
  done
  
  # add fabric profile into a container that will be added to the ensemble
  ensemble_profile_args="$managed_profile_args --profile fabric"
}

getApplicationList(){
  unset application_list  
    
  i=0
  while read line # Read a line
  do
    if [[ $line != \#* ]] && [ -n "$line" ]; then
      app=`echo $line | cut -f1 -d"="`
      application_list[i]=$app
      i=$(($i + 1))
    fi

  done < $application_properties_file
  
}

chooseEnvironment(){
  available_environments_list=( $available_environments )
  available_environments_list+=('newEnvironment')
  available_environments_list+=('removeEnvironment')
  
  echo "Enter number of the desired environment:"
  select chosen_environment in "${available_environments_list[@]}"
  do
    echo "Environment chosen: $chosen_environment"
    break
  done
  
  if [ -z "$chosen_environment" ]; then
    echo "Invalid choice, try again."
    chooseEnvironment
  else
    if [ "$chosen_environment" = "newEnvironment" ]; then
      newEnvironment
      chooseEnvironment
    elif [ "$chosen_environment" = "removeEnvironment" ]; then
      removeEnvironment
      chooseEnvironment      
    else
      getProfilesForApplication
      container_name_prefix="${chosen_application}_${chosen_environment}_"
      container_name_prefix_length=${#container_name_prefix}
    fi
  fi
}

removeEnvironment(){
  available_environments_list=( $available_environments )
  
  echo "Enter number of the desired environment:"
  select remove_environment in "${available_environments_list[@]}"
  do
    echo "Environment chosen to remove: $remove_environment"
    break
  done
  
  echo "Are you sure you want to delete environment: $remove_environment"
  echo "Enter [y/n]"
  read should_remove
  
  if [ "$should_remove" == "y" ]; then
    echo "Removing environment $remove_environment"
    remove=($remove_environment)
    available_environments_list=( "${available_environments_list[@]/$remove}" )
    
    old_available_environments=$available_environments
    
    # Put space between all the environments 
    available_environments=`printf -- '%s ' "${available_environments_list[@]}"`
    
    # strip all leading/trailing whitespace
    available_environments=`echo $available_environments | sed -e 's/^ *//' -e 's/ *$//'`
    sed -i "s/$old_available_environments/$available_environments/" $USER_PROPS_FILE
  else
    echo "Environment $remove_environment will not be deleted"
  fi
}

newEnvironment(){
  echo "Input environment name:"
  read environment
  
  # determine if the environment already exists
  environment_exists="false"
  available_environments_list=( $available_environments )
  for i in "${available_environments_list[@]}"
  do
    if [ "$i" == "$environment" ]; then
      environment_exists="true"
    fi
  done
  
  # only add the environment if it does not already exist
  if [ "$environment_exists" == "true" ]; then
    echo "Error, environment \"$environment\" already exists. Please input a non-existent environment"
    newEnvironment
  else
    echo "Adding environment $environment"
    old_available_environments=$available_environments
    available_environments="$available_environments $environment"
    sed -i "s/$old_available_environments/$available_environments/" $USER_PROPS_FILE
  fi
}

checkIfFuseRunning(){

  # only propmpt for fuse connection string if env properties are not set
  if [ -z "$ENSEMBLE_SERVER_HOST" ]; then
    promptForFuseConnection
  fi

  connected="false"
  while [ $connected != "true" ];
  do
    setScriptCommand    
    echo "Ensuring Fuse is running."
    if [ $DEBUG == "true" ]; then
      echo "Using fuse connection string:"
      echo $FUSE_CLIENT_SCRIPT
    fi
    
    # just run a simple command to make sure we can connect to fuse
    command_result=`$FUSE_CLIENT_SCRIPT "version" | grep -vP "\x1b\x5b\x6d"`
    script_exit_val=$?
    if [[ $script_exit_val != 0 ]]; then
      echo "Error connecting to Fuse, try again."
      promptForFuseConnection
    else    
      echo "Able to connect to Fuse."
      connected="true"
    fi 
  done
}

setScriptCommand(){
   # build the fuse client script options
  if [ $ENSEMBLE_SERVER_HOST == "localhost" ]; then
    # if local do not need options
    FUSE_CLIENT_SCRIPT=$FUSE_CLIENT_SCRIPT_PATH
  else
    # add user, host and port
    FUSE_CLIENT_SCRIPT="$FUSE_CLIENT_SCRIPT_PATH -u $ENSEMBLE_SERVER_USER -h $ENSEMBLE_SERVER_HOST -a $ENSEMBLE_SERVER_PORT"
	
    # only include password if one is provided
    if [ -n "$ENSEMBLE_SERVER_PASSWORD" ]; then
      FUSE_CLIENT_SCRIPT="$FUSE_CLIENT_SCRIPT -p $ENSEMBLE_SERVER_PASSWORD "
    fi
    
    CONTAINER_CONNECT_COMMAND=`echo $FUSE_CLIENT_SCRIPT "fabric:container-connect -u $ENSEMBLE_SERVER_USER -p $ENSEMBLE_SERVER_PASSWORD"`
  fi
}

promptForFuseConnection(){
  echo "Enter hostname of server running Fuse:"
  if [ -z "$ENSEMBLE_SERVER_HOST" ]; then
    default_ENSEMBLE_SERVER_HOST="localhost"
  else
    default_ENSEMBLE_SERVER_HOST=$ENSEMBLE_SERVER_HOST
  fi
  echo "Default: $default_ENSEMBLE_SERVER_HOST"
  read ENSEMBLE_SERVER_HOST
  ENSEMBLE_SERVER_HOST=${ENSEMBLE_SERVER_HOST:-$default_ENSEMBLE_SERVER_HOST}
  
  # If fuse is local host then just use defaults for the client script
  if [ $ENSEMBLE_SERVER_HOST != "localhost" ]; then
  
    echo "Enter Fuse user:"
    if [ -n "$ENSEMBLE_SERVER_USER" ]; then
      default_ENSEMBLE_SERVER_USER=$ENSEMBLE_SERVER_USER
      echo "Default: $default_ENSEMBLE_SERVER_USER"
    fi
    read ENSEMBLE_SERVER_USER
    ENSEMBLE_SERVER_USER=${ENSEMBLE_SERVER_USER:-$default_ENSEMBLE_SERVER_USER}
    
    echo "Enter Fuse user password, or leave empty if no pw needed:"
    if [ -n "$ENSEMBLE_SERVER_PASSWORD" ]; then
      default_ENSEMBLE_SERVER_PASSWORD=$ENSEMBLE_SERVER_PASSWORD
      echo "Default: $default_ENSEMBLE_SERVER_PASSWORD"
    fi
    read ENSEMBLE_SERVER_PASSWORD    
    ENSEMBLE_SERVER_PASSWORD=${ENSEMBLE_SERVER_PASSWORD:-$default_ENSEMBLE_SERVER_PASSWORD}
    
    echo "Enter Fuse port:"
    if [ -n "$ENSEMBLE_SERVER_PORT" ]; then
      default_ENSEMBLE_SERVER_PORT=$ENSEMBLE_SERVER_PORT
    else
      default_ENSEMBLE_SERVER_PORT="8101"
    fi
    echo "Default: $default_ENSEMBLE_SERVER_PORT"
    read ENSEMBLE_SERVER_PORT    
    ENSEMBLE_SERVER_PORT=${ENSEMBLE_SERVER_PORT:-$default_ENSEMBLE_SERVER_PORT}
    
    echo "Using Fuse client script options: $FUSE_CLIENT_SCRIPT"
  else
    FUSE_CLIENT_SCRIPT="$FUSE_CLIENT_SCRIPT_PATH"
  fi
}


checkIfFabricCreated(){
  echo "Ensuring fabric has been created."
  
  fabric_installed=`$FUSE_CLIENT_SCRIPT config:list | grep "service.pid = io.fabric8.agent"`
  
  if [ -z "$fabric_installed" ]; then
    echo "Fabric not installed. Should it be created? [y/n]"
    read create_fabric
    create_fabric=${create_fabric:-y}
    if [ $create_fabric == "y" ]; then
      echo "Creating fabric."
      if [ $DEBUG = true ]; then
	echo $FUSE_CLIENT_SCRIPT "fabric:create --clean --resolver localip --profile fabric --verbose --wait-for-provisioning"
      fi
      $FUSE_CLIENT_SCRIPT "fabric:create --clean --resolver localip --profile fabric --verbose --wait-for-provisioning"
    else
      echo "Fabric will not be created, script exiting."
      exit
    fi
  else
    fabric_connected=`$FUSE_CLIENT_SCRIPT "fabric:container-list" | grep -vP "\x1b\x5b\x6d"`
    
    if [[ $fabric_connected == *Command* ]]; then
      echo "Error Fabric is not connected. There has been a system error, please contact a System Administrator."
      exit 1
    else
      echo "Fabric has been created."
    fi  
  fi 
 
}

waitUntilProvisioned(){
  container=$1
  
  info_command="$FUSE_CLIENT_SCRIPT container-info $1"
  
  container_exists=`$info_command`
  if [[ $container_exists == "Container $container does not exists!" ]]; then
    echo "Error waiting on provisioning, container does not exist!"
  else

    echo "Waiting for container: $container to provision"
    sleep 10
    while : 
    do
      
      # Get the third token from the "Provision Status" line
      status=`$info_command  | grep "Provision Status:" |awk '{print $3}'`
      
      echo "current status: $status"
      
      if [ -z $status ]; then
	status="unknown"
      fi
	
      if [ $status == "success" ]; then
	echo "Successfully provisioned container: $container"
	break
      fi
      
      
      i=$[$i+1]
      
      if [ $i -gt 25 ]; then
	echo "Timeout waiting for container: $container to provision"
	echo "Container info: "
	$info_command
	exit 1
      fi
      
      sleep 10
      
    done
  fi
}

readContainers(){
  
  num_rows=$1
  num_columns=2  
   
  confirm_message="The following containers have been input with profile: $profile_args"
  for ((i=1;i<=num_rows;i++)) do
      
      echo "Enter container (instance) $i hostname:"
      read hostname
      
      # index of container takes into account the last index of the pre-existent containers
      container_index=$(($last_index + $i)) 
      
      # name of container is the prefix with the index
      container_name=${container_name_prefix}$container_index
           
      confirm_message="$confirm_message\n\tContainer $i, hostname: $hostname, username: $FUSE_USER, instance name: $container_name"
      
      server_list[$i]="$hostname $container_name"

  done
  confirm_message="$confirm_message\nAre these values correct? [y/n]"
  echo -e $confirm_message
  read confirm
  
  if [ $confirm == "n" ]; then
    readContainers $num_rows
  fi
   
}

getAllContainerList(){
  echo "Retrieving container list from Fabric"
  filter=$1
  # Get list of conatinser with the correct prefix
  # grep -vP "\x1b\x5b\x6d" strips off the ^]]m that shows up 
  output=`$FUSE_CLIENT_SCRIPT fabric:container-list $container_name_prefix | grep -vP "\x1b\x5b\x6d" | egrep -v "provision status$filter" | awk '{print $1}'`
  if [[ $output == Error* ]] || [[ $output == Command* ]] || [[ $output == Failed* ]]; then
    echo "Error obtaining fabric container list. Error msg:"
    echo -e $output
    echo "Has fabric:create been run on the root?"
    exit
  fi 
  output=`echo $output | sed -e 's/^ *//' -e 's/ *$//'`
  container_array=( $output )
  filter=""
  chosen_app=''
}

chooseContainer(){
  exclude_all_option=$1
  
  getAllContainerList $choose_filter
  
  declare -a choice_list
  
  index=0
  for i in "${container_array[@]}"
  do
    :
    # remove '*' character from root
    if [ -z $leave_star_on_root ]; then
      container_array[$index]=`echo ${container_array[$index]} | sed 's/\*$//'`
    fi
    choice_list[$index]=${container_array[$index]}
    index=$(($index + 1))
  done
  
  if [ $index == 0 ]; then
    echo "No containers found for application $chosen_application in environment $chosen_environment."
    chosen_container=""
  elif [ $index == 1 ];then # no need for select menu if only one container
    chosen_container="${choice_list[0]}"
    echo "Only one container found, using container $chosen_container"
  else
    
    # Add all choice if there is more than one option and told to include the all option
    if [ $index -gt 1 ] && [ -z $exclude_all_option ]; then
	choice_list[$index]="ALL"
    fi  
    
    echo "Enter number of the desired container: "
    chosen_container=""
    while [ -z "$chosen_container" ];
    do
      select chosen_container in "${choice_list[@]}"
      do
	if [ -z "$chosen_container" ]; then
	  echo "Invalid option, try again."
	fi
	break
      done
    done
    echo "Container chosen: $chosen_container"
  fi
  choose_filter=""

}

chooseNonEnsembleContainer(){
  choose_filter="$choose_filter|ensemble"
  chooseContainer $1
}

getAmqStatsForContainer(){
  container=$1
  echo "Stats for container: $container"
  command=`echo "$CONTAINER_CONNECT_COMMAND $container activemq:dstat"`
  echo $command
  command_result=`exec $command`
  if [[ $command_result == *Command* ]]; then
    echo "Activemq command not found, container $container does not have a running broker."
  else
    echo -e "$command_result"
  fi
}

instanceStatus(){
  echo "Include feature stats? (Default:n) [y/n]"
  read includeFeatures  
  includeFeatures=${includeFeatures:n}

  chooseContainer
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      echo "Container status for $i"
      getContainerStats $i
    done
  else
    getContainerStats $chosen_container
  fi
}

getContainerStats(){
  $FUSE_CLIENT_SCRIPT fabric:container-info $1
  
  if [ "$includeFeatures" == "y" ]; then
     $CONTAINER_CONNECT_COMMAND "$1 features:list -i"
  fi
}

# Sets the number of ensemble containers to the $ensemble_count variable
getEnsembleCount(){
 ensemble_count=`$FUSE_CLIENT_SCRIPT ensemble-list | grep -v "\[id\]" | grep -vP "\x1b\x5b\x6d" | wc -l`
}

installInstance(){
  
  echo "Should the containers also be Zookeeper Registry member containers? [y/n]"
  echo -e "\tDefault: n"
  read ensemble_container
  ensemble_container=${ensemble_container:-n}

  declare -a server_list

  createContainers
}

createContainers(){
  
   if [ "$ensemble_container" == "y" ]; then
      profile_args="$ensemble_profile_args"
      echo "How many Zookeeper Registry member containers (instances) should be created?"
   else
      profile_args="$managed_profile_args"
      echo "How many Fabric managed application containers (instances) should be created?"
   fi
  read application_count   
  
  if [ "$ensemble_container" == "y" ]; then
    # To add to ensemble make sure there will be at least three containers
    getEnsembleCount
    num_ensemble_containers=$(($ensemble_count + $application_count))
    if [ $num_ensemble_containers -lt 3 ]; then
      echo "Error, there must be at least three Zookeeper Registry member containers (instances)."
      echo "Adding $application_count Zookeeper Registry member containers would give a total of $num_ensemble_containers Zookeeper Registry member containers"
      echo "Please try again with more containers."
      createContainers
      return
    fi
    
    # It is recommended to have odd number of containers, so give warning and a chance to start over
    rem=$(( $num_ensemble_containers % 2 ))
    if [ $rem -eq 0 ]; then
      echo "Warning, it is recommended to have an odd number of ensemble servers."
      echo "Adding $application_count containers would bring the total ensemble count to ${num_ensemble_containers}."
      echo "Are you sure you want to proceed? [y/n]"
      read proceed
      
      if [ "$proceed" == "n" ]; then
	echo "Trying again with a different number of containers."
	createContainers
	return
      else
	echo "Proceeding with even number of ensemble containers."
      fi
    fi
    echo "Will add $application_count instances to the list of Zookeeper Registry member containers"
  else
    echo "Will create $application_count managed instances."
  fi
   
  # get list of containers that start with application_env_
  result=`$FUSE_CLIENT_SCRIPT container-list $container_name_prefix | grep -vP "\x1b\x5b\x6d" | grep -v "provision status" | awk '{print $1}' | grep -vP "\x1b\x5b\x6d" `
  containers_array=( $result ) # list of all containers for the combo of env/app
  last_container=`echo $result | rev | cut -d ' ' -f1 | rev` # returns the name of the last container
  last_index=${last_container:$container_name_prefix_length} # index of the last container, strips off the "application_env_" prefix, what remains is the index
  
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list  | grep -vP "\x1b\x5b\x6d" | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=( $availableVersions )
  
  versionCount=${#availableVersionsArray[@]}
  
  # prompt for the version if multiple versions are found
  if [ $versionCount -gt 1 ];then 
    echo "What version should be used?"
    version=""
    while [ -z "$version" ];
    do
      select version in "${availableVersionsArray[@]}"
      do
	if [ -z "$version" ]; then
	  echo "Invalid option, try again."
	fi    
	break
      done
    done
    echo "Using version: $version"  
  else # only older versions are found
    echo "Only one version found, using version: $availableVersions"
    version=$availableVersions
  fi

  # get the user input for container host, etc
  readContainers $application_count
  
  # only needed when installing a set of ensemble containers
  ensemble_list=""
  
  # Loop through and create all the containers
  for ((j=1;j<=application_count;j++)) do
  
    # input from user hostname selection
    server=`echo ${server_list[$j]} | awk '{print $1}'` 
    
    # name of container is the prefix with the index
    container=`echo ${server_list[$j]} | awk '{print $2}'` 
    
    # only needed when installing a set of ensemble containers
    ensemble_list="$ensemble_list $container"
    
    # install the container
    echo "Installing container: $container to server: $server with profiles: $profile_args" 
    if [ $DEBUG = true ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --resolver localip --path $container_path $profile_args --version $version --user $FUSE_USER --jvm-opts '$app_container_jvm_props' $container"
    fi
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --resolver localip --path $container_path  $profile_args --version $version --user $FUSE_USER --jvm-opts '$app_container_jvm_props' $container"`
    echo -e "$result"
    if [[ "$result" == *Error* ]] || [[ "$result" == *failed* ]]; then
      echo "Error creating container: $container"
      break;
    fi
        
    # remove the zip file that was transferred
    remove_command="ssh $FUSE_USER@$server rm -f $container_path/$container/$ZIP_FILENAME"
    echo "Removing fabric zip file: $remove_command"    
    $remove_command
    
    # let the container completely start before moving on to the next
    waitUntilProvisioned $container
    
  done
  
  # add containers to ensemble if told not a simple managed instance
  if [ "$ensemble_container" == "y" ]; then
    echo "Adding $ensemble_list to the Zookeeper Registry Group"
    if [ $DEBUG ]; then
      echo "$FUSE_CLIENT_SCRIPT \"fabric:ensemble-add -f $ensemble_list\""
    fi
    ensemble_add_result=`$FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"`
    echo -e "$ensemble_add_result"
    
    if [[ "$ensemble_add_result" == *Error* ]] || [[ "$ensemble_add_result" == *failed* ]]; then
      echo "Error adding $ensemble_list to the Zookeeper Registry Group."
      echo "Containers $ensemble_list have been created but not joined to the Zookeeper Registry Group."
      echo "To later add containers run the following command from the Fuse Command line:"
      echo -e "\t$FUSE_CLIENT_SCRIPT \"fabric:ensemble-add -f $ensemble_list\""
      return;
    fi

    echo "Waiting for provisioning"
    $FUSE_CLIENT_SCRIPT fabric:wait-for-provisioning
  fi
  
  # Display all the containers to the user
  echo "Current containers:"
  $FUSE_CLIENT_SCRIPT "fabric:container-list $container_name_prefix"
  
  # display the updated ensemble list if the containers were added to the ensemble
  if [ "$ensemble_container" == "y" ]; then
    echo "Current list of Zookeeper Registry member containers:"
    $FUSE_CLIENT_SCRIPT ensemble-list
  fi
}

stopInstance(){
  
  chooseContainer
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      # Only shut down non root containers, The root container (ends in "*" needs osgi:shutdown
      if [[ $i != *\* ]]; then	
	shutdownContainer $i
      fi
    done
    
    #echo "Should the root container also be shutdown? [y/n]"
    #read shutdown_root
    
    #if [ $shutdown_root == "y" ]; then
    #  echo "Shutting down root."
    #  $FUSE_CLIENT_SCRIPT "osgi:shutdown --force"
    #  echo "Root shutdown, exiting script."
    #  exit 0
    #fi
    
  else
    # Make sure chosen container is not the root
    if [[ $chosen_container != *\* ]]; then	
      shutdownContainer $chosen_container
    else
      echo "Shutting down root."
      $FUSE_CLIENT_SCRIPT "osgi:shutdown --force"
      echo "Root shutdown, exiting script."
      exit 0
    fi
  fi  
  
  # set variable back to empty to not distrupt other methods
  leave_star_on_root=""
}

removeInstance(){

  chooseContainer
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  # list of all the ensemble members, each on its own line
  full_ensemble_list=`$FUSE_CLIENT_SCRIPT ensemble-list | grep -vP "\x1b\x5b\x6d"`
      
  if [ $chosen_container == "ALL" ]; then
    ensemble_remove_list=""
    remove_from_ensemble_count=0
    for i in "${container_array[@]}"
    do
      :
      # see if the full ensemble list contains this container
      ensemble_member=`echo -e "$full_ensemble_list" | egrep "^${i}$"`
      if [ -n "$ensemble_member" ]; then
	ensemble_remove_list="$ensemble_remove_list $i"
	remove_from_ensemble_count=$[$remove_from_ensemble_count + 1]
      fi
    done
    
    # Make sure removing the ensemble containers would not put Fabric in an unallowable state
    getEnsembleCount
    new_ensemble_count=$[${ensemble_count}-${remove_from_ensemble_count}]
    if [ $new_ensemble_count -eq 2 ]; then
      echo "Error, the Zookeeper Registry Group cannot contain just 2 containers. Container cannot be removed."
      echo "Removing the following containers from the Zookeeper Registry group would bring the total to 2:"
      echo -e "\t$ensemble_remove_list"
      echo "Current list of Zookeeper Registry members:"
      $FUSE_CLIENT_SCRIPT fabric:ensemble-list
      return
    fi
    
    # Only perform ensemble-remove if there are ensemble containers
    if [ -z "$ensemble_remove_list" ]; then
      echo "All chosen containers are managed containers"
    else
      # remove the containers from the ensemble
      echo "Removing the following member containers from Zookeeper Registry Group:"
      echo -e "\t$ensemble_remove_list"
      if [ $DEBUG = true ]; then
	echo "$FUSE_CLIENT_SCRIPT \"fabric:ensemble-remove $ensemble_remove_list\""    
      fi
      ensemble_remove_result=`$FUSE_CLIENT_SCRIPT "fabric:ensemble-remove --force $ensemble_remove_list"`
      echo -e "$ensemble_remove_result"
      if [[ "$ensemble_remove_result" == *Error* ]] || [[ "$ensemble_remove_result" == *failed* ]]; then
	echo "Error removing $ensemble_list to the Zookeeper Registry Group."
	echo "Containers will not be deleted."
	echo "Contact a system adminstrator to fix the environment and then try again."
	return
      fi
    fi
    
    # now delete all of the containers
    for i in "${container_array[@]}"
    do
      :
      if [ -n "$i" ]; then
	removeContainer $i    
      fi
    done        
  else
    echo "Are you sure you want to delete container \"${chosen_container}\"? (Default: y) [y/n]"
    read confirm
    confirm=${confirm:-y}
    
    if [ "$confirm" != "y" ]; then
      echo "Told not to delete ${chosen_container}."
      return
    fi
  
    # see if the full ensemble list contains this container
    ensemble_member=`echo -e "$full_ensemble_list" | egrep "^${chosen_container}$"`
    if [ -n "$ensemble_member" ]; then
      getEnsembleCount
    
      # To add to ensemble make sure there will be at least two containers
      num_containers=$(($ensemble_count - 1))
      if [ $num_containers -eq 2 ]; then
	echo "Error, the Zookeeper Registry Group cannot contain just 2 containers. Container \"$chosen_container\" cannot be removed."
	echo "Current list of Zookeeper Registry members"
	$FUSE_CLIENT_SCRIPT fabric:ensemble-list
	return
      fi
      
      # Remove the container from the ensemble
      echo "Removing member container $chosen_container from Zookeeper Registry Group"
      if [ $DEBUG = true ]; then
	echo "$FUSE_CLIENT_SCRIPT \"fabric:ensemble-remove --force $chosen_container\""
      fi
      ensemble_remove_result=`$FUSE_CLIENT_SCRIPT "fabric:ensemble-remove --force $chosen_container"`
      echo -e "$ensemble_remove_result"
      if [[ "$ensemble_remove_result" == *Error* ]] || [[ "$ensemble_remove_result" == *failed* ]]; then
	echo "Error removing $chosen_container from the Zookeeper Registry Group."
	echo "Container will not be deleted."
	echo "Contact a system adminstrator to fix the environment and then try again."
	return
      fi
      
    else
      echo "Container $chosen_container is not a member of the Zookeeper Registry Group."
    fi
  
    #Delete the container
    removeContainer $chosen_container  
  fi  
}

removeContainer(){
  remove_container=$1

  echo "Deleting container $remove_container"
  if [ $DEBUG = true ]; then
      echo "$FUSE_CLIENT_SCRIPT container-delete --force $remove_container"    
  fi
  $FUSE_CLIENT_SCRIPT "container-delete --force $remove_container"  
}

shutdownContainer(){
  
  container=$1
  
  pid=`$FUSE_CLIENT_SCRIPT fabric:container-info $container | grep "Process ID" | awk '{print $3}'`
  if [ $pid == "null" ]; then
    echo "Container $container already shutdown, skipping."
  else
  
    $FUSE_CLIENT_SCRIPT "container-stop --force $container"
    
    retry_count="1"
    
    # wait for the container to show as shutdownContainer
    echo "Waiting for container $container to shutdown"
    while : 
    do
      :
      pid=`$FUSE_CLIENT_SCRIPT fabric:container-info $container | grep "Process ID" | awk '{print $3}'`
      
      if [ -z $pid ]; then
	echo "Error getting status for container: $container, will not wait until shutdown is confirmed."
	break;
      fi
    
      if [ $pid = "null" ]; then
	echo "Container $container is shutdown."
	break;
      fi
      
      retry_count=$[$retry_count+1]
      
      if [ $retry_count -gt 25 ]; then
	echo "Timeout waiting for container: $container to shutdown"
	echo "Container info: "
	$FUSE_CLIENT_SCRIPT container-info $container
	exit 1
      fi
      
      sleep 10
      
    done
  fi
}

startInstance(){
  chooseContainer
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      startupContainer $i
    done
  else
    startupContainer $chosen_container
  fi  
}

startupContainer(){
  
  container=$1
  $FUSE_CLIENT_SCRIPT "container-start $container"
  
  i="1"
  
  pid=`$FUSE_CLIENT_SCRIPT fabric:container-info $container | grep "Process ID" | awk '{print $3}'`
  if [ $pid != "null" ]; then
    echo "Container $container already started, skipping."
  else
    # wait for the container to show as shutdownContainer
    echo "Waiting for container $container to startup"
    while : 
    do
      :
      pid=`$FUSE_CLIENT_SCRIPT fabric:container-info $container | grep "Process ID" | awk '{print $3}'`
    
      if [ $pid != "null" ]; then
	echo "Container $container has started. Waiting for provisioning."
	waitUntilProvisioned $container
	break;
      fi
      
      i=$[$i+1]
      
      if [ $i -gt 25 ]; then
	echo "Timeout waiting for container: $container to startup"
	echo "Container info: "
	$FUSE_CLIENT_SCRIPT container-info $container
	exit 1
      fi
      
      sleep 10
      
    done
  fi
  
}

instanceConnect(){
  chooseContainer "exclude_all_option"
  
  run_again="y"
  
  while [ $run_again == "y" ];
  do
    echo "This option will run the input command against the Fuse Command Console of the selected container (instance)."
    echo "For a reference of available commands see Fuse documentation:" 
    echo -e "\thttps://access.redhat.com/documentation/en-US/Red_Hat_JBoss_Fuse/6.1/html/Console_Reference/files/ConsoleRefIntro.html"
    echo "Enter Fuse command to run:"
    read command
    
    if [ -z "$command" ]; then
      echo "Error, you must enter a command. Try again."
      continue
    fi
    
    if [ $DEBUG = true ]; then
      echo "executing: $CONTAINER_CONNECT_COMMAND $chosen_container $command"
    else
      echo "Executing $command on container $chosen_container"
    fi
    echo "output:"
    
    $CONTAINER_CONNECT_COMMAND "$chosen_container $command"
    
    echo "Run another command? [y/n]"
    read run_again
    command=""
    
  done
  
    
}

activeMQStats(){
  chooseContainer
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      getAmqStatsForContainer $i
    done
  else
      getAmqStatsForContainer $chosen_container
  fi
}

addProfile(){
  chooseContainer
  
  echo "What profile to add?"
  read profile
  
  if [ $chosen_container == "ALL" ]; then
    for container in "${container_array[@]}"
    do
      :
      addProfileToContainer $container $profile
    done
  else
      addProfileToContainer $chosen_container $profile
  fi
}

addProfileToContainer(){
  container=$1
  profile=$2
  echo "Adding profile $profile to container $container"
  $FUSE_CLIENT_SCRIPT "container-add-profile $container $profile"
  waitUntilProvisioned $container
  echo "Container $container updated:"
  $FUSE_CLIENT_SCRIPT "container-info $container"
}

removeProfile(){
  chooseContainer
    
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      echo "What profile should be removed from all non ensemble containers?"
      read profile
      removeProfileFromContainer $i $profile
    done
  else
      output=`$FUSE_CLIENT_SCRIPT "container-info $chosen_container" | grep "Profiles:" | cut -d ":" -f2`
      profile_array=($output)
      num_profiles="${#profile_array[@]}"
      if [ $num_profiles -eq 1 ]; then
	echo "Only one profile associated with container \"${chosen_container}\", are you sure you want to proceed?"
	echo "Warning, do so will revert the container to the \"default\" profile"
	echo "Do you want to proceed? (Default: n) [y/n]"
	read proceed
	proceed=${proceed:-n}
	
	if [ $proceed == "n" ]; then
	  echo "Exiting profile remove."
	  return
	fi
	profile="${profile_array[0]}"
      else
	echo "Enter number of the desired profile to remove: "
	profile=""
	while [ -z "$profile" ];
	do
	  select profile in "${profile_array[@]}"
	  do
	    if [ -z "$profile" ]; then
	      echo "Invalid option, try again."
	    fi  
	    break
	  done      
	done
      fi
      echo "Removing profile: $profile"
      removeProfileFromContainer $chosen_container $profile
  fi
}

removeProfileFromContainer(){
  container=$1
  profile=$2
  $FUSE_CLIENT_SCRIPT "container-remove-profile $container $profile"
  waitUntilProvisioned $container
  echo "Container $container updated:"
  $FUSE_CLIENT_SCRIPT "container-info $container"
}

camelRouteStart(){
  chooseContainer "exclude_all_option"
  
  # TODO - only select stopped routes
  output=`$CONTAINER_CONNECT_COMMAND $chosen_container camel:route-list | grep -v Status | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  if [[ "$output" == executing* ]]; then
    echo "No Camel routes found on conatiner"
    return
  fi
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired route to start: "
    route=""
    while [ -z "$route" ];
    do
      select route in "${route_list[@]}"
      do
	if [ -z "$route" ]; then
	  echo "Invalid option, try again."
	fi
	break
      done
    done
    echo "Starting route: $route"
    $CONTAINER_CONNECT_COMMAND $chosen_container camel:route-start $route
  else
    echo "No routes found in container"
  fi
}

camelRouteInfo(){
  chooseContainer "exclude_all_option"
  
  # TODO - only select stopped routes
  output=`$CONTAINER_CONNECT_COMMAND "$chosen_container camel:route-list" | grep -v Status | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  echo -e "$output"
  if [[ "$output" == executing* ]]; then

    echo "No Camel routes found on conatiner"
    return
  fi
  
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired route to get info: "
    route=""
    while [ -z "$route" ];
    do
      select route in "${route_list[@]}"
      do
	if [ -z "$route" ]; then
	  echo "Invalid option, try again."
	fi
	break
      done
    done
    echo "Getting info for route: $route"
    $CONTAINER_CONNECT_COMMAND $chosen_container camel:route-info $route
  else
    echo "No routes found in container"
  fi
}

camelRouteStop(){
  chooseContainer "exclude_all_option"
  
  # TODO - only select started routes
  output=`$CONTAINER_CONNECT_COMMAND $chosen_container camel:route-list | grep -v Status | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  if [[ "$output" == executing* ]]; then
    echo "No Camel routes found on conatiner"
    return
  fi
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired route to stop: "
    route=""    
    while [ -z "$route" ]; 
    do
      select route in "${route_list[@]}"
          do
	  if [ -z "$route" ]; then
	    echo "Invalid option, try again."
	  fi
	  break
	done
    done
    echo "Stopping route: $route"
    stop_command=`echo "$CONTAINER_CONNECT_COMMAND $chosen_container camel:route-stop $route"`      
    if [ $DEBUG = true ]; then      
      echo $stop_command
    fi
    $stop_command
  else
    echo "No routes found in container"
  fi
}

instanceUpgrade(){

  chooseContainer
  
  if [ $chosen_container == "ALL" ]; then
    upgradeAllContainers
  else
    upgradeSingleContainer
  fi
  
}

upgradeAllContainers(){
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -vP "\x1b\x5b\x6d" | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
    
  echo "What version should all containers be upgraded to?"
  version=""
  while [ -z "$version" ];
  do
    select version in "${availableVersionsArray[@]}"
    do
      if [ -z "$version" ]; then
	echo "Invalid option, try again."
      fi
      
      break
    done
  done
  echo "version chosen: $version"    
  result=`$FUSE_CLIENT_SCRIPT "fabric:container-upgrade --all $version" | grep -vP "\x1b\x5b\x6d"`
  echo "$result"
  
  # break out if an error occurred
  if [[ $result == Error* ]] ; then
    echo "Error performing container upgrade."      
    break
  fi
      
  echo "Waiting for provisioning"
  $FUSE_CLIENT_SCRIPT "fabric:wait-for-provisioning"
  
  echo "Accept changes? (Default:y) [y/n]:"
  read acceptChanges  
  acceptChanges=${acceptChanges:-y}
  if [ $acceptChanges == "n" ]; then
  
    echo "What version should all containers be rolled back to?"
    rollbackVersion=""
    while [ -z "$rollbackVersion" ];
    do
      select rollbackVersion in "${availableVersionsArray[@]}"
      do
	if [ -z "$rollbackVersion" ]; then
	  echo "Invalid option, try again."
	fi
	
	break
      done
    done
    $FUSE_CLIENT_SCRIPT "fabric:container-rollback --all $rollbackVersion"
    echo "Waiting for provisioning"
    $FUSE_CLIENT_SCRIPT "fabric:wait-for-provisioning"
  fi
}

readPassword(){
  password=""
  
  while : 
  do
    echo "Enter Password:"
    read -s password
    
    echo "Confirm Password:"
    read -s password_confirm
    
    if [ $password == $password_confirm ]; then
      break
    fi
    
    echo "Passwords do not match, try again."
    
  done
  

}

upgradeSingleContainer(){
  # find current version of the container
  echo "upgrade single"
  curVersion=`$FUSE_CLIENT_SCRIPT "container-info $chosen_container" | grep -vP "\x1b\x5b\x6d" | grep "Version:" | awk '{print $2}'`
  
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -vP "\x1b\x5b\x6d" | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
  
  # make list with only newer versions as you cannot upgrade to older version
  declare -a newerVersions
  index=1
  for avail in "${availableVersionsArray[@]}"
  do
    :
    # compare available version to the version on the container
    compareVersions $curVersion $avail
    if [ $newerVersion = "true" ];
    then
      newerVersions[$index]=$avail
      index=$[$index+1]
    fi
  done
  
  if [ $index -gt 1 ];then # there are newer versions than that found on container available
    echo "Current version: $curVersion"
    echo "Select new version:"
    version=""
    while [ -z "$version" ];
    do
      select version in "${newerVersions[@]}"
      do
	if [ -z "$version" ]; then
	  echo "Invalid option, try again."
	fi
	break
      done
    done
    echo "version selected: $version"
    if [ $DEBUG == "true" ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-upgrade $version $chosen_container" | grep -vP "\x1b\x5b\x6d"
    fi
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-upgrade $version $chosen_container" | grep -vP "\x1b\x5b\x6d"`
    echo "$result"
  
    # break out if an error occurred
    if [[ $result == Error* ]] ; then
      echo "Error performing container upgrade."      
      break
    fi
    
    waitUntilProvisioned $chosen_container
    echo "Accept changes? (Default:y) [y/n]:"
    read acceptChanges  
    acceptChanges=${acceptChanges:-y}
    if [ $acceptChanges == "n" ]; then
      echo "Rolling back changes."
      if [ $DEBUG == "true" ]; then
	echo $FUSE_CLIENT_SCRIPT "fabric:container-rollback $curVersion $chosen_container"
      fi
      $FUSE_CLIENT_SCRIPT "fabric:container-rollback $curVersion $chosen_container"
      waitUntilProvisioned $chosen_container
    else
      echo "Changes accepted."
    fi
      
  else # only older versions are found
    echo "No newer version than $curVersion found. Versions available:"
    printf "%s " "${availableVersionsArray[@]}"
  fi
}

instanceRollback(){

  chooseContainer
  
  if [ $chosen_container == "ALL" ]; then
    rollbackAllContainers
  else
    rollbackSingleContainer
  fi
  
}

rollbackAllContainers(){
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -vP "\x1b\x5b\x6d" | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
    
  echo "What version should all containers be rolled back to?"
  version=""
  while [ -z "$version" ];
  do
    select version in "${availableVersionsArray[@]}"
    do
      if [ -z "$version" ]; then
	echo "Invalid option, try again."
      fi
	  
      break
    done
  done
  
  echo "version selected: $version"
  result=`$FUSE_CLIENT_SCRIPT "fabric:container-rollback --all $version" | grep -vP "\x1b\x5b\x6d"`
  echo "$result"
  
  # break out if an error occurred
  if [[ $result == Error* ]] ; then
    echo "Error performing container rollback."      
    break
  fi
  
  # rollback was successful if we got here, wait for provisioning
  echo "Waiting for provisioning"
  $FUSE_CLIENT_SCRIPT "fabric:wait-for-provisioning"
}

rollbackSingleContainer(){
  # find current version of the container
  curVersion=`$FUSE_CLIENT_SCRIPT "container-info $chosen_container" | grep -vP "\x1b\x5b\x6d" | grep "Version:" | awk '{print $2}'`
  
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -vP "\x1b\x5b\x6d" | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
  
  # make list with only older versions as you cannot rollback to a newer version
  declare -a olderVersions
  index=1
  for avail in "${availableVersionsArray[@]}"
  do
    :
    # compare available version to the version on the container
    compareVersions $avail $curVersion
    if [ $newerVersion = "true" ];
    then
      olderVersions[$index]=$avail
      index=$[$index+1]
    fi
  done
  
  if [ $index -gt 1 ];then # there are older versions than that found on container available
    echo "Current version: $curVersion"
    echo "Select new version:"
    version=""
    while [ -z "$version" ];
    do
      select version in "${olderVersions[@]}"
      do
	if [ -z "$version" ]; then
	  echo "Invalid option, try again."
	fi
	break
      done
    done
    
    echo "version selected: $version"
    if [ $DEBUG == "true" ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-rollback $version $chosen_container"
    fi
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-rollback $version $chosen_container" | grep -vP "\x1b\x5b\x6d"`
    echo "$result"
  
    # break out if an error occurred
    if [[ $result == Error* ]] ; then
      echo "Error performing container rollback."      
      break
    fi
    
    waitUntilProvisioned $chosen_container
	  
  else # only older versions are found
    echo "No version older than $curVersion found. Versions available:"
    printf "%s " "${availableVersionsArray[@]}"
  fi
}

environmentInfo(){
  echo "Detailed info? (Default:n) [y/n]"
  read detailed
  detailed=${detailed:-n}
  $FUSE_CLIENT_SCRIPT "fabric:container-list $container_name_prefix"
  
  if [ $detailed == "y" ]; then
    getAllContainerList
    for container in "${container_array[@]}"
    do
      :
      # Remove and trailing '*' character
      container=`echo $container | sed 's/\*$//'`
      echo "Detailed info for container: $container"
      $FUSE_CLIENT_SCRIPT "fabric:container-info $container"
    done
  fi
}

sshToInstanceUser(){
  chooseContainer "exclude_all_option"
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  host=`$FUSE_CLIENT_SCRIPT fabric:container-info $chosen_container | grep -vP "\x1b\x5b\x6d" | grep "Network Address:" | awk '{print $3}'`
   
  run_again="y"
  
  while [ $run_again == "y" ];
  do
    echo "Enter Bash command to run:"
    read command
    
    if [ -z "$command" ]; then
      echo "Error, you must enter a command. Try again."
      continue
    fi
    
    echo "executing: ssh $FUSE_USER@$host $command"
    echo "output:"
    
    ssh $FUSE_USER@$host $command
    
    echo "Run another command? [y/n]"
    read run_again
    command=""
    
  done
}

# Compares two versions. Will set $newerVersion variable to true if $1 is newer or false if it is older
compareVersions(){
  # it isn't newer if it is the same version
  if [ $1 == $2 ]; then
    newerVersion="false"
    return
  fi
  
  # split the versions into a space delimited string of the major then minor versions
  current=`echo $1 | sed 's/\./ /g'`
  check=`echo $2 | sed 's/\./ /g'`
  
  # turn each version into an array with the major version the first element
  currentArray=($current)
  checkArray=($check)

  size_of_cur=${#currentArray[@]}    
  
  for ((i=0;i<=size_of_cur-1;i++)) do
  
    # the current has more minor versions, so it is newer
    if [ -z "${checkArray[$i]}" ];then
      newerVersion="false"
      return 
    fi
    
    if [ ${currentArray[$i]} -gt ${checkArray[$i]} ]; then
      newerVersion="false"
      return 
    fi
    
    if [ ${currentArray[$i]} -lt ${checkArray[$i]} ]; then
      newerVersion="true"
      return 
    fi
  done
  
  newerVersion="true"
  
}

threadDump(){
  # Choose an application container, don't allow for an "ALL" option
  chooseContainer "exclude_all_option"
  
  if [ -z "$chosen_container" ]; then
    echo "Unable to perform thread dump if there are no application containers"
  else    
    # Get host and pid of chosen_container
    container_info=`$FUSE_CLIENT_SCRIPT fabric:container-info $chosen_container | grep -vP "\x1b\x5b\x6d"`
    host=`echo -e "$container_info" | grep "Network Address:" | awk '{print $3}'`
   
    pid=`echo -e "$container_info" | grep "Process ID:" | awk '{print $3}'`
    
    if [ $pid == "null" ]; then
      echo "Error, Container is not running, cannot generate thread dump."
    else
                  
      # prompt for a local file to write thread dump to
      echo "Enter file path to write thread dump to:"
      default_file=$LOGS/thread-dump-`date +%m%d%Y-%H%M%S`.out
      echo "Default: $default_file"
      read file
      file=${file:-$default_file}
      
      # Run jstack command remotely
      ssh_command="ssh $FUSE_USER@$host jstack $pid"
      echo "executing $ssh_command"
      ssh_output=`$ssh_command`
      
      # write thread dump to file
      echo "writing thread dump to $file"
      echo -e "$ssh_output" > $file
	  
    fi
   fi
}