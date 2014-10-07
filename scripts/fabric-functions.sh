DEBUG=true

if [ -z $FUSE_HOME ]; then
  FUSE_HOME=/home/kevin/software/fuse/jboss-fuse-6.1.0.redhat-379
fi
FUSE_BIN=$FUSE_HOME/bin
FUSE_CLIENT_SCRIPT=$FUSE_BIN/client

FUSE_USER=`whoami`

if [ ! -f $FUSE_CLIENT_SCRIPT ]; then
  echo "Error: Fuse client script does not exist at $FUSE_CLIENT_SCRIPT"
  exit 1
fi

waitUntilProvisioned(){
  container=$1
  
  info_command="$FUSE_CLIENT_SCRIPT container-info $1"

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
      echo "Successfully provisioned server"
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
}

readContainers(){
  
  num_rows=$1
  num_columns=2  
  
  if [ -z $profile ]; then
    # if no profile then it is an ensemble install
    profile="ensemble"
    default_container_name_prefix="ensemble_container_"
    default_user="fabric8"
  else
    # add underscore to profile name
    default_container_name_prefix=$profile"_"
    default_user=$profile
  fi

  confirm_message="The following containers have been input with profile: $profile"
  for ((i=1;i<=num_rows;i++)) do
      
      echo "Enter container $i hostname:"
      read hostname
      echo "Enter container $i container_name:" 
      echo "Default: [$default_container_name_prefix$i]"
      read container_name
      container_name=${container_name:-$default_container_name_prefix$i}
      echo "Enter container $i username:"
      echo "Default: [$default_user]"
      read username
      username=${username:-$default_user}
      
      confirm_message="$confirm_message\n\tContainer $i, hostname: $hostname, container_name: $container_name, username: $username"
      
      server_list[$i]="$hostname $container_name"
      
  done
  confirm_message="$confirm_message\nAre these values correct? [y/n]"
  echo -e $confirm_message
  read confirm
  
  if [ $confirm == "n" ]; then
    readContainers $num_rows
  fi
  
  echo -e $confirm_message
   
}

getAllContainerList(){
  echo "Retrieving container list from Fabric"
  filter=$1
  output=`$FUSE_CLIENT_SCRIPT fabric:container-list | egrep -v "provision status$filter" | awk '{print $1}'`
  echo -e $output
  if [[ $output == Error* ]] || [[ $output == Command* ]] || [[ $output == Failed* ]]; then
    echo "Error obtaining fabric container list. Error msg:"
    echo -e $output
    echo "Has fabric:create been run on the root?"
    exit
  fi
  container_array=($output)
}

chooseContainer(){
  exclude_all=$1
  
  getAllContainerList $choose_filter
  
  declare -a choice_list
  
  index=0
  for i in "${container_array[@]}"
  do
    :
    # remove '*' character from root
    if [ $i == "root*" ]; then
	container_array[$index]="root"
    fi
    choice_list[$index]=${container_array[$index]}
    index=$[$index+1]
  done
  
  # Add all choice if there is more than one option and told to include the all option
  if [ $index -gt 1 ] && [ -z $exclude_all ]; then
      choice_list[$index]="ALL"
  fi  
  
  echo "Enter number of the desired container: "
  select chosen_container in "${choice_list[@]}"
  do
    echo "Container chosen: $chosen_container"
    break
  done

}

chooseNonEnsembleContainer(){
  choose_filter="|ensemble"
  chooseContainer 
}

getAmqStatsForContainer(){
  container=$1
  echo "Stats for container: $container"
  $FUSE_CLIENT_SCRIPT fabric:container-connect $container activemq:dstat
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

installEnsemble(){

  declare -a server_list
  echo "Note: There should be an even number of ensemble containers created since localhost will also be in the ensemble."
  echo "How many ensemble containers should be created?"
  read ensemble_count

  readContainers ensemble_count

  ensemble_list=""

  for ((j=1;j<=ensemble_count;j++)) do

    server=`echo ${server_list[$j]} | awk '{print $1}'`
    container=`echo ${server_list[$j]} | awk '{print $2}'`
    ensemble_list="$ensemble_list $container"
    echo "Installing container: $container to server: $server"
    if [ $DEBUG = true ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path --user $FUSE_USER $container"
    fi
    $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path --user $FUSE_USER $container"

    waitUntilProvisioned $container
    
  done
  
  if [ $DEBUG ]; then
    echo $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"
  fi
  echo "Creating ensemble"
  $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"

  sleep 10
  echo "Ensemble created:"
  $FUSE_CLIENT_SCRIPT fabric:ensemble-list

}

installApp(){

  declare -a server_list
  echo "How many application containers should be created?"
  read application_count
  echo "What fabric profile should be used?"
  read profile

  readContainers application_count

  for ((j=1;j<=application_count;j++)) do

    server=`echo ${server_list[$j]} | awk '{print $1}'`
    container=`echo ${server_list[$j]} | awk '{print $2}'`
    echo "Installing container: $container to server: $server with profile: $profile" 
    if [ $DEBUG = true ]; then
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path --profile $profile --user $FUSE_USER $container"
    fi
    $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --path $container_path  --profile $profile --user $FUSE_USER $container"

    waitUntilProvisioned $container
    
  done
  
  echo "Current containers:"
  $FUSE_CLIENT_SCRIPT "fabric:container-list"
  
}

stopContainer(){
  chooseContainer
  if [ $chosen_container == "ALL" ]; then
    for i in "${container_array[@]}"
    do
      :
      shutdownContainer $i
    done
  else
    shutdownContainer $chosen_container
  fi  
}

shutdownContainer(){
  
  container=$1
  $FUSE_CLIENT_SCRIPT "container-stop --force $container"
  
  retry_count="1"
  
  # wait for the container to show as shutdownContainer
  echo "Waiting for container to shutdown"
  while : 
  do
    :
    pid=`$FUSE_CLIENT_SCRIPT fabric:container-info $container | grep "Process ID" | awk '{print $3}'`
    echo pid: $pid
  
    if [ $pid = "null" ]; then
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
  
}

startContainer(){
  chooseContainer
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
  
  # wait for the container to show as shutdownContainer
  echo "Waiting for container to startup"
  while : 
  do
    :
    pid=`$FUSE_CLIENT_SCRIPT fabric:container-info $container | grep "Process ID" | awk '{print $3}'`
    echo pid: $pid
  
    if [ $pid != "null" ]; then
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
  
}

containerConnect(){
  chooseContainer
  $FUSE_CLIENT_SCRIPT fabric:container-connect $chosen_container  
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
  chooseNonEnsembleContainer
  
  # TODO - only select stopped routes
  output=`$FUSE_CLIENT_SCRIPT container-connect $chosen_container camel:route-list | grep -v Context | grep -v "Command not found" | grep -v "\\-\\-\\-" | awk '{print $2}'`
  echo output: $output
  route_list=($output)
  
  size=${#route_list[@]}
  
  if [ $size -gt 0 ]; then
    echo "Enter number of the desired profile to start: "
    select route in "${route_list[@]}"
    do
      echo "Starting route: $route"
      echo "not yet implemented"
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
      if [ $container == "root*" ]; then
	container="root"
      fi
      echo "Detailed info for container: $container"
      $FUSE_CLIENT_SCRIPT "fabric:container-info $container"
    done
  fi
}

sshToContainer(){
  chooseContainer "exclude_all"
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