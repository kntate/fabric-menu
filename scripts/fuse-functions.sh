DEBUG=true

if [ -z $FUSE_HOME ]; then
  FUSE_HOME=$fuse_home_default
fi
FUSE_BIN=$FUSE_HOME/bin
FUSE_CLIENT_SCRIPT_PATH=$FUSE_BIN/client

ZIP_FILENAME="fabric8-karaf-1.0.0.redhat-379.zip"

hidden_password="******"

# Make sure client script exists
if [ ! -f $FUSE_CLIENT_SCRIPT ]; then
  echo "Error: Fuse client script does not exist at $FUSE_CLIENT_SCRIPT"
  exit 1
fi

checkIfFuseRunning(){
  echo "Enter hostname of server running Fuse:"
  if [ -z "$fuse_host" ]; then
    default_fuse_host="localhost"
  else
    default_fuse_host=$fuse_host
  fi
  echo "Default: $default_fuse_host"
  read fuse_host
  fuse_host=${fuse_host:-$default_fuse_host}
  
  # If fuse is local host then just use defaults for the client script
  if [ $fuse_host != "localhost" ]; then
  
    echo "Enter Fuse user:"
    if [ -n "$fuse_user" ]; then
      default_fuse_user=$fuse_user
      echo "Default: $default_fuse_user"
    fi
    read fuse_user
    fuse_user=${fuse_user:-$default_fuse_user}
    
    echo "Enter Fuse user password, or leave empty if no pw needed:"
    if [ -n "$fuse_password" ]; then
      default_fuse_password=$fuse_password
      echo "Default: $default_fuse_password"
    fi
    read fuse_password    
    fuse_password=${fuse_password:-$default_fuse_password}

    
    echo "Enter Fuse port:"
    if [ -n "$fuse_port" ]; then
      default_fuse_port=$fuse_port
    else
      default_fuse_port="8101"
    fi
    echo "Default: $default_fuse_port"
    read fuse_port    
    fuse_port=${fuse_port:-$default_fuse_port}
    
    FUSE_CLIENT_SCRIPT="$FUSE_CLIENT_SCRIPT_PATH -u $fuse_user -h $fuse_host -a $fuse_port"
    
    # only include password if one is provided
    if [ -n "$fuse_password" ]; then
      FUSE_CLIENT_SCRIPT="$FUSE_CLIENT_SCRIPT -p $fuse_password "
    fi
    
    echo "Using Fuse client script options: $FUSE_CLIENT_SCRIPT"
  else
    FUSE_CLIENT_SCRIPT="$FUSE_CLIENT_SCRIPT_PATH"
  fi

  echo "Ensuring Fuse is running."
  # just run a simple command to make sure we can connect to fuse
  command_result=`$FUSE_CLIENT_SCRIPT "version"`
  script_exit_val=$?
  if [[ $script_exit_val != 0 ]]; then
    echo "Error connecting to Fuse, try again."
    checkIfFuseRunning
  else    
    echo "Able to connect to Fuse."
  fi
  
  
}

checkIfFabricCreated(){
  echo "Ensuring fabric has been created."
  command_result=`$FUSE_CLIENT_SCRIPT "fabric:container-list"`
  
  if [[ $command_result == *Command* ]]; then
    echo "Fabric not installed. Should it be created? [y/n]"
    read create_fabric
    create_fabric=${create_fabric:-n}
    if [ $create_fabric == "y" ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:create --wait-for-provisioning"
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
  
  if [ -z "$profile" ]; then
    # if no profile then it is an ensemble install
    profile="ensemble"
    default_container_name_prefix="ensemble_container_"
    default_user="fabric8"
  else
    first_profile=`echo $profile | awk '{print $1}'`
    # add underscore to profile name
    default_container_name_prefix=$first_profile"_"
    default_user=$first_profile
  fi

  confirm_message="The following containers have been input with profile: $profile"
  for ((i=1;i<=num_rows;i++)) do
      
      echo "Enter container $i hostname:"
      read hostname
      echo "Enter container $i username:"
      echo "Default: [$default_user]"
      read username
      username=${username:-$default_user}
      echo "Enter password for $username"
      readPassword
      
      confirm_message="$confirm_message\n\tContainer $i, hostname: $hostname, username: $username, password: $hidden_password"
      
      server_list[$i]="$hostname $username $password"

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
  output=`$FUSE_CLIENT_SCRIPT fabric:container-list $chosen_app | egrep -v "provision status$filter" | awk '{print $1}'`
  if [[ $output == Error* ]] || [[ $output == Command* ]] || [[ $output == Failed* ]]; then
    echo "Error obtaining fabric container list. Error msg:"
    echo -e $output
    echo "Has fabric:create been run on the root?"
    exit
  fi
  container_array=($output)
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
    index=$[$index+1]
  done
  
  if [ $index == 0 ]; then
    echo "No matching conatiners found."
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
  command_result=`$FUSE_CLIENT_SCRIPT fabric:container-connect $container activemq:dstat`
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
     $FUSE_CLIENT_SCRIPT fabric:container-connect $1 "features:list -i"
  fi
}

installApp(){

  declare -a server_list
  echo "How many application containers should be created?"
  read application_count
  
  # TODO make sure profile exists??
  echo "What application?" 
  read profile
  
  echo "What environment?"
  read environment
  
  container_name_prefix="${profile}_${environment}_"
  container_name_prefix_length=${#container_name_prefix}
    
  # find all versions available in fabric
  availableVersions=`$FUSE_CLIENT_SCRIPT fabric:version-list | grep -v "# containers" | awk '{print $1}'`
  availableVersionsArray=($availableVersions)
  
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
  
  result=`$FUSE_CLIENT_SCRIPT container-list $container_name_prefix | grep -v "provision status" | awk '{print $1}' `
  last_container=`echo $result | cut -d ' ' -f2`
  last_index=${last_container:$container_name_prefix_length}
  start_index=$(($last_index + 1))

  readContainers $application_count
  
  ensemble_list=""
  
  for ((j=1;j<=application_count;j++)) do

    container_index=$(($last_index + $j))
  
    server=`echo ${server_list[$j]} | awk '{print $1}'`
    username=`echo ${server_list[$j]} | awk '{print $2}'`
    password=`echo ${server_list[$j]} | awk '{print $3}'`
    container=${container_name_prefix}$container_index
    ensemble_list="$ensemble_list $container"
    echo "Installing container: $container to server: $server with profile: $profile" 
    if [ $DEBUG = true ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path --profile $profile --version $version --user $username --password $hidden_password --jvm-opts '$app_container_jvm_props' $container"
    fi
    result=`$FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path  --profile $profile --version $version --user $username --password $password --jvm-opts '$app_container_jvm_props' $container"`
    echo -e "$result"
    if [[ $result == Error* ]]; then
      echo "Error creating container: $container"
      break;
    fi
    
    remove_command="ssh $username@$server rm -f $container_path/$container/$ZIP_FILENAME"
    echo "Removing fabric zip file: $remove_command"
    
    $remove_command
    
    waitUntilProvisioned $container
    
  done
  echo "ensemble-add $ensemble_list"
  if [ $DEBUG ]; then
    echo $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"
  fi
  echo "Creating ensemble"
  $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"

  $FUSE_CLIENT_SCRIPT fabric:wait-for-provisioning
  
  echo "Current containers:"
  $FUSE_CLIENT_SCRIPT "fabric:container-list"
  
}

stopContainer(){
  # When chosing container, leave the * at the end of the root name because this container cannot be shutdown with container-stop.
  # Instead osgi:shutdown should be used.
  leave_star_on_root="leave_star_on_root"
  chooseNonEnsembleContainer
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
  echo "Which application?"
  read chosen_app
  chooseNonEnsembleContainer
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      echo "$FUSE_CLIENT_SCRIPT container-delete $i"    
      $FUSE_CLIENT_SCRIPT container-delete $i    
    done        
  else
    echo "$FUSE_CLIENT_SCRIPT container-delete $chosen_container"
    $FUSE_CLIENT_SCRIPT container-delete $chosen_container    
  fi  
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
      echo pid: $pid
      
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
  chooseNonEnsembleContainer 
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
      echo pid: $pid
    
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
    
    echo "executing: $FUSE_CLIENT_SCRIPT fabric:container-connect $chosen_container $command"
    echo "output:"
    
    $FUSE_CLIENT_SCRIPT fabric:container-connect $chosen_container $command
    
    echo "Run another command? [y/n]"
    read run_again
    
  done
  
    
}

activeMQStats(){
  chooseNonEnsembleContainer
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
  chooseNonEnsembleContainer
  
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
  chooseNonEnsembleContainer "exclude_all_option"
  
  # TODO - only select stopped routes
  output=`$FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-list | grep -v Status | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  echo output: $output
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired route to start: "
    select route in "${route_list[@]}"
    do
      echo "Starting route: $route"
      $FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-start $route
      break
    done
  else
    echo "No routes found in container"
  fi
}

camelRouteInfo(){
  chooseNonEnsembleContainer "exclude_all_option"
  
  # TODO - only select stopped routes
  output=`$FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-list | grep -v Status | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  echo output: $output
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired route to get info: "
    select route in "${route_list[@]}"
    do
      echo "Getting info for route: $route"
      $FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-info $route
      break
    done
  else
    echo "No routes found in container"
  fi
}

camelRouteStop(){
  chooseNonEnsembleContainer "exclude_all_option"
  
  # TODO - only select started routes
  output=`$FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-list | grep -v Status | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  echo output: $output
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired route to stop: "
    select route in "${route_list[@]}"
    do
      echo "Stopping route: $route"
      $FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-stop $route
      break
    done
  else
    echo "No routes found in container"
  fi
}

containerUpgrade(){

  chooseoCntainer
  
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
  $FUSE_CLIENT_SCRIPT "fabric:container-list"
  
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
  host=`$FUSE_CLIENT_SCRIPT fabric:container-info $chosen_container | grep "Network Address:" | awk '{print $3}'`
  
  first_profile=`$FUSE_CLIENT_SCRIPT fabric:container-list | grep -v "provision status" | grep $chosen_container | awk '{print $4}' | sed 's/,$//'`
  # The container is an ensemble
  if [ $first_profile == "default" ]; then
    first_profile="fabric8"
  fi
  
  echo "Enter OS username for host $host"
  echo "Default [$first_profile]"
  read username
  username=${username:-$first_profile}
  
  run_again="y"
  
  while [ $run_again == "y" ];
  do
    echo "Enter command to run:"
    read command
    
    echo "executing: ssh $username@$host $command"
    echo "output:"
    
    ssh $username@$host $command
    
    echo "Run another command? [y/n]"
    read run_again
    
  done
}

threadDump(){
  # Choose an application container, don't allow for an "ALL" option
  chooseNonEnsembleContainer "exclude_all_option"
  
  if [ -z "$chosen_container" ]; then
    echo "Unable to perform thread dump if there are no application containers"
  else
    
    # Get host and pid of chosen_container
    container_info=`$FUSE_CLIENT_SCRIPT fabric:container-info $chosen_container`
    host=`echo -e "$container_info" | grep "Network Address:" | awk '{print $3}'`
    pid=`echo -e "$container_info" | grep "Process ID:" | awk '{print $3}'`
    
    if [ $pid == "null" ]; then
      echo "Error, Container is not running, cannot generate thread dump."
    else
      
      # Find first profile for the chosen_container
      first_profile=`$FUSE_CLIENT_SCRIPT fabric:container-list | grep -v "provision status" | grep $chosen_container | awk '{print $4}' | sed 's/,$//'`
      # The container is an ensemble
      if [ $first_profile == "default" ]; then
	first_profile="fabric8"
      fi
      
      # Get os username, default to same as the first profile in the container
      echo "Enter OS username for host $host"
      echo "Default [$first_profile]"
      read username
      username=${username:-$first_profile}
      
      # prompt for a local file to write thread dump to
      echo "Enter file path to write thread dump to:"
      default_file=$LOGS/thread-dump-`date +%m%d%Y-%H%M%S`.out
      echo "Default: $default_file"
      read file
      file=${file:-$default_file}
      
      # Run jstack command remotely
      ssh_command="ssh $username@$host jstack $pid"
      echo "executing $ssh_command"
      ssh_output=`$ssh_command`
      
      # write thread dump to file
      echo "writing thread dump to $file"
      echo -e "$ssh_output" > $file
	  
    fi
   fi
}