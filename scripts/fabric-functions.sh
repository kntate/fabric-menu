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

  for ((i=1;i<=num_rows;i++)) do
      
      echo "Enter container $i hostname"
      read hostname
      echo "Enter container $i container_name"
      read container_name
      
      server_list[$i]="$hostname $container_name"
      
  done

}

getAllContainerList(){
  echo "Retrieving container list from Fabric"
  filter=$1
  output=`$FUSE_CLIENT_SCRIPT fabric:container-list | egrep -v "provision status$filter" | awk '{print $1}'`
  container_array=($output)
}

chooseContainer(){
  filter=$1
  getAllContainerList $filter
  
  declare -a choice_list
  
  index=0
  for i in "${container_array[@]}"
  do
    :
    if [ $i == "root*" ]; then
	container_array[$index]="root"
    fi
    choice_list[$index]=${container_array[$index]}
    index=$[$index+1]
  done
  
  # Add all choice if there is more than one option
  if [ $index -gt 2 ]; then
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
  chooseContainer "|ensemble"
}

getAmqStatsForContainer(){
  container=$1
  echo "Stats for container: $container"
  $FUSE_CLIENT_SCRIPT fabric:container-connect $container activemq:dstat
}

containerStatus(){
  echo "Include feature stats? (Default:n) [y/n]"
  read includeFeatures  
  includeFeatures=${includeFeatures:-Richard}

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
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --user $FUSE_USER $container"
    fi
    $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --user $FUSE_USER $container"

    waitUntilProvisioned $container
    
  done
  
  echo $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"
  $FUSE_CLIENT_SCRIPT "fabric:ensemble-add -f $ensemble_list"

  sleep 2
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
      echo $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --profile $profile --user $FUSE_USER $container"
    fi
    $FUSE_CLIENT_SCRIPT "fabric:container-create-ssh --host $server --profile $profile --user $FUSE_USER $container"

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
  $FUSE_CLIENT_SCRIPT container-stop $container
  
  i="1"
  
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
    
    i=$[$i+1]
    
    if [ $i -gt 25 ]; then
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
  chooseContainer
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
    for i in "${container_array[@]}"
    do
      :
      addProfileToContainer $i $profile
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
      break
    done
  else
    echo "No routes found in container"
  fi
}