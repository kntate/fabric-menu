#!/bin/bash 

if [ -z $FUSE_HOME ]; then
  FUSE_HOME=$fuse_home_default
fi
FUSE_BIN=$FUSE_HOME/bin
FUSE_CLIENT_SCRIPT_PATH=$FUSE_BIN/client
FUSE_USER=`whoami`

ZIP_FILENAME="fabric8-karaf-1.0.0.redhat-379.zip"

hidden_password="******"

# Make sure client script exists
if [ ! -f $FUSE_CLIENT_SCRIPT ]; then
  echo "Error: Fuse client script does not exist at $FUSE_CLIENT_SCRIPT"
  exit 1
fi

chooseApplication(){
  getApplicationList

  echo "Enter number of the desired application:"
  select chosen_application in "${application_list[@]}"
  do
    echo "Application chosen: $chosen_application"
    break
  done
  
  getProfilesForApplication
       
}

getProfilesForApplication(){
  application=$1
  profiles=`egrep ^$chosen_application= $application_properties_file | cut -f2 -d"="`
  profile_list=( $profiles )
  profile_args=""
  for profile in "${profile_list[@]}"
  do
    profile_args="$profile_args --profile $profile"
  done
}

getApplicationList(){
    
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
  
  echo "Enter number of the desired environment:"
  select chosen_environment in "${available_environments_list[@]}"
  do
    echo "Environment chosen: $chosen_environment"
    break
  done
    
  container_name_prefix="${chosen_application}_${chosen_environment}_"
  container_name_prefix_length=${#container_name_prefix}
}

checkIfFuseRunning(){

  # only propmpt for fuse connection string if env properties are not set
  if [ -z "$ENSEMBLE_SERVER_HOST" ]; then
    promptForFuseConnection
  fi

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
    
    CONTAINER_CONNECT_COMMAND=`echo $FUSE_CLIENT_SCRIPT "fabric:container-connect -u admin -p admin"`
  fi

  echo "Ensuring Fuse is running."
  if [ $DEBUG == "true" ]; then
    echo "Using fuse connection string:"
    echo $FUSE_CLIENT_SCRIPT
  fi
  
  # just run a simple command to make sure we can connect to fuse
  command_result=`$FUSE_CLIENT_SCRIPT "version"`
  script_exit_val=$?
  if [[ $script_exit_val != 0 ]]; then
    echo "Error connecting to Fuse, try again."
    promptForFuseConnection
  else    
    echo "Able to connect to Fuse."
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
  command_result=`$FUSE_CLIENT_SCRIPT "fabric:container-list"`
  
  if [[ $command_result == *Command* ]]; then
    echo "Fabric not installed. Should it be created? [y/n]"
    read create_fabric
    create_fabric=${create_fabric:-y}
    if [ $create_fabric == "y" ]; then
      if [ $DEBUG = true ]; then
	echo $FUSE_CLIENT_SCRIPT "fabric:create --clean --profile fabric --verbose --wait-for-provisioning"
      fi
      $FUSE_CLIENT_SCRIPT "fabric:create --clean --profile fabric --verbose --wait-for-provisioning"
    else
      echo "Fabric will not be created, script exiting."
      exit
    fi
  else
    echo "Fabric has been created."
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

  default_container_name_prefix=${chosen_application}"_"
  
  default_hostname=""
 
  confirm_message="The following containers have been input with profile: $profile_args"
  for ((i=1;i<=num_rows;i++)) do
      
      echo "Enter container $i hostname:"
      if [ -n "$default_hostname" ]; then
	echo "Default: $default_hostname"
      fi
      read hostname
      if [ -n "$default_hostname" ]; then
	hostname=${hostname:-$default_hostname}
      fi
      default_hostname=$hostname
      echo "Enter password for $FUSE_USER"
      readPassword
      
      confirm_message="$confirm_message\n\tContainer $i, hostname: $hostname, username: $FUSE_USER, password: $hidden_password"
      
      server_list[$i]="$hostname $password"

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
        
    index=$(($index + 1))
  done
  
  if [ $index == 0 ]; then
    echo "No conatiners found for application $chosen_application in environment $chosen_environment."
    chosen_container=""
  else
    
    # Add all choice if there is more than one option and told to include the all option
    if [ $index -gt 1 ] && [ -z $exclude_all_option ]; then
	choice_list[$index]="ALL"
    fi  
    
    echo "Enter number of the desired container: "
    select chosen_container in "${choice_list[@]}"
    do
      echo "Container chosen: $chosen_container"
      break
    done
    
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

containerStatus(){
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
  
  if [ $includeFeatures == "y" ]; then
     $CONTAINER_CONNECT_COMMAND "$1 features:list -i"
  fi
}

installApp(){

  declare -a server_list
  echo "How many application containers should be created?"
  read application_count
    
  result=`$FUSE_CLIENT_SCRIPT container-list $container_name_prefix | grep -v "provision status" | awk '{print $1}'`
  containers_array=( $result )
  last_index=${#containers_array[@]} # Get the length.                                          
  
  # To add to ensemble make sure there will be at least two containers
  num_containers=$(($last_index + $application_count))
  if [ $num_containers -lt 2 ]; then
    echo "Error, there must be at least two application containers in the environment."
    return
  fi
    
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list  | grep -vP "\x1b\x5b\x6d" | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=( $availableVersions )
  
  versionCount=${#availableVersionsArray[@]}
  
  if [ $versionCount -gt 1 ];then 
    echo "What version should be used?"
    select version in "${availableVersionsArray[@]}"
    do
      echo "Using version: $version"      
      break
    done
  else # only older versions are found
    echo "Only one version found, using version: $availableVersions"
    version=$availableVersions
  fi

  readContainers $application_count
  
  ensemble_list=""
  
  for ((j=1;j<=application_count;j++)) do

    container_index=$(($last_index + $j))
  
    server=`echo ${server_list[$j]} | awk '{print $1}'`
    password=`echo ${server_list[$j]} | awk '{print $2}'`
    container=${container_name_prefix}$container_index
    ensemble_list="$ensemble_list $container"
    echo "Installing container: $container to server: $server with profiles: $profile_args" 
    if [ $DEBUG = true ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path $profile_args --version $version --user $FUSE_USER --password $hidden_password --jvm-opts '$app_container_jvm_props' $container"
    fi
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path  $profile_args --version $version --user $FUSE_USER --password $password --jvm-opts '$app_container_jvm_props' $container"`
    echo -e "$result"
    if [[ $result == Error* ]]; then
      echo "Error creating container: $container"
      break;
    fi
    
    remove_command="ssh $FUSE_USER@$server rm -f $container_path/$container/$ZIP_FILENAME"
    echo "Removing fabric zip file: $remove_command"
    
    $remove_command
    
    waitUntilProvisioned $container
    
  done
  echo "Adding $ensemble_list to the ensemble"
  if [ $DEBUG ]; then
    echo $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"
  fi
  $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"

  echo "Waiting for provisioning"
  $FUSE_CLIENT_SCRIPT fabric:wait-for-provisioning
  
  echo "Current containers:"
  $FUSE_CLIENT_SCRIPT "fabric:container-list $container_name_prefix"
  
}

stopContainer(){
  
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

removeApp(){

  chooseContainer
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  if [ $chosen_container == "ALL" ]; then
    all_containers=`echo "${container_array[@]}"`
    echo "Removing container $all_containers from ensemble"
    if [ $DEBUG = true ]; then
      echo "$FUSE_CLIENT_SCRIPT fabric:ensemble-remove $all_containers"    
    fi
    $FUSE_CLIENT_SCRIPT "fabric:ensemble-remove --force $all_containers"
    for i in "${container_array[@]}"
    do
      :
      if [ -n "$i" ]; then
	removeContainer $i    
      fi
    done        
  else
    echo "Removing container $chosen_container from ensemble"
    if [ $DEBUG = true ]; then
      echo "$FUSE_CLIENT_SCRIPT fabric:ensemble-remove $chosen_container"    
    fi
    $FUSE_CLIENT_SCRIPT "fabric:ensemble-remove --force $chosen_container"
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

startContainer(){
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
  $FUSE_CLIENT_SCRIPT container-start $container
  
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

containerConnect(){
  chooseContainer "exclude_all_option"
  
  run_again="y"
  
  while [ $run_again == "y" ];
  do
    echo "Enter command to run:"
    read command
    
    if [ $DEBUG = true ]; then
      echo "executing: $CONTAINER_CONNECT_COMMAND $chosen_container $command"
    else
      echo "Executing $command on container $chosen_container"
    fi
    echo "output:"
    
    $CONTAINER_CONNECT_COMMAND "$chosen_container $command"
    
    echo "Run another command? [y/n]"
    read run_again
    
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
  chooseNonEnsembleContainer
    
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
      echo "Enter number of the desired profile to remove: "
      select profile in "${profile_array[@]}"
      do
	echo "Removing profile: $profile"
	break
      done
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
    select route in "${route_list[@]}"
    do
      echo "Starting route: $route"
      $CONTAINER_CONNECT_COMMAND $chosen_container camel:route-start $route
      break
    done
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
    select route in "${route_list[@]}"
    do
      echo "Getting info for route: $route"
      $CONTAINER_CONNECT_COMMAND $chosen_container camel:route-list
      $CONTAINER_CONNECT_COMMAND $chosen_container camel:route-info $route
      break
    done
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
    select route in "${route_list[@]}"
    do
      echo "Stopping route: $route"
      stop_command=`echo "$CONTAINER_CONNECT_COMMAND $chosen_container camel:route-stop $route"`      
      if [ $DEBUG = true ]; then      
	echo $stop_command
      fi
      $stop_command
      break
    done
  else
    echo "No routes found in container"
  fi
}

containerUpgrade(){

  chooseContainer
  
  if [ $chosen_container == "ALL" ]; then
    upgradeAllContainers
  else
    upgradeSingleContainer
  fi
  
}

upgradeAllContainers(){
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
    
  echo "What version should all containers be upgraded to?"
  select version in "${availableVersionsArray[@]}"
  do
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-upgrade --all $version"`
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
      select rollbackVersion in "${availableVersionsArray[@]}"
      do
	$FUSE_CLIENT_SCRIPT "fabric:container-rollback --all $rollbackVersion"
	echo "Waiting for provisioning"
	$FUSE_CLIENT_SCRIPT "fabric:wait-for-provisioning"
	
	break
      done
    fi
    
    break
  done
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
    
    echo "Passwords do not match, try again"
    
  done
  

}

upgradeSingleContainer(){
  # find current version of the container
  curVersion=`$FUSE_CLIENT_SCRIPT "container-info $chosen_container" | grep "Version:" | awk '{print $2}'`
  
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
  
  # make list with only newer versions as you cannot upgrade to older version
  declare -a newerVersions
  index=1
  for avail in "${availableVersionsArray[@]}"
  do
    :
    # compare available version to the version on the container
    if awk "BEGIN {exit !($avail > $curVersion)}"
    then
      newerVersions[$index]=$avail
      index=$[$index+1]
    fi
  done
  
  if [ $index -gt 1 ];then # there are newer versions than that found on container available
    echo "Current version: $curVersion"
    echo "Select new version:"
    select version in "${newerVersions[@]}"
    do
      result=`$FUSE_CLIENT_SCRIPT "fabric:container-upgrade $version $chosen_container"`
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
	$FUSE_CLIENT_SCRIPT "fabric:container-rollback $curVersion $chosen_container"
	waitUntilProvisioned $chosen_container
      fi
      
      break
    done
  else # only older versions are found
    echo "No newer version than $curVersions found. Versions available:"
    printf "%s " "${availableVersionsArray[@]}"
  fi
}

containerRollback(){

  chooseContainer
  
  if [ $chosen_container == "ALL" ]; then
    rollbackAllContainers
  else
    rollbackSingleContainer
  fi
  
}

rollbackAllContainers(){
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
    
  echo "What version should all containers be rolled back to?"
  select version in "${availableVersionsArray[@]}"
  do
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-rollback --all $version"`
    echo "$result"
    
    # break out if an error occurred
    if [[ $result == Error* ]] ; then
      echo "Error performing container rollback."      
      break
    fi
    
    # rollback was successful if we got here, wait for provisioning
    echo "Waiting for provisioning"
    $FUSE_CLIENT_SCRIPT "fabric:wait-for-provisioning"
        
    break
  done
}

rollbackSingleContainer(){
  # find current version of the container
  curVersion=`$FUSE_CLIENT_SCRIPT "container-info $chosen_container" | grep "Version:" | awk '{print $2}'`
  
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
  
  # make list with only older versions as you cannot rollback to a newer version
  declare -a olderVersions
  index=1
  for avail in "${availableVersionsArray[@]}"
  do
    :
    # compare available version to the version on the container
    if awk "BEGIN {exit !($avail < $curVersion)}"
    then
      olderVersions[$index]=$avail
      index=$[$index+1]
    fi
  done
  
  if [ $index -gt 1 ];then # there are older versions than that found on container available
    echo "Current version: $curVersion"
    echo "Select new version:"
    select version in "${olderVersions[@]}"
    do
      result=`$FUSE_CLIENT_SCRIPT "fabric:container-rollback $version $chosen_container"`
      echo "$result"
    
      # break out if an error occurred
      if [[ $result == Error* ]] ; then
	echo "Error performing container rollback."      
	break
      fi
      
      waitUntilProvisioned $chosen_container
            
      break
    done
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

sshToContainer(){
  chooseContainer "exclude_all_option"
  
  if [ -z "$chosen_container" ]; then
    return
  fi
  
  host=`$FUSE_CLIENT_SCRIPT fabric:container-info $chosen_container | grep "Network Address:" | awk '{print $3}'`
   
  run_again="y"
  
  while [ $run_again == "y" ];
  do
    echo "Enter command to run:"
    read command
    
    echo "executing: ssh $FUSE_USER@$host $command"
    echo "output:"
    
    ssh $FUSE_USER@$host $command
    
    echo "Run another command? [y/n]"
    read run_again
    
  done
}

threadDump(){
  # Choose an application container, don't allow for an "ALL" option
  chooseContainer "exclude_all_option"
  
  if [ -z "$chosen_container" ]; then
    echo "Unable to perform thread dump if there are no application containers"
  else
    activeMQStats
    # Get host and pid of chosen_container
    container_info=`$FUSE_CLIENT_SCRIPT fabric:container-info $chosen_container`
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