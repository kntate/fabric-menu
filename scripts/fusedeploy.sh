#!/bin/bash 

BaseDir=${0%/*}
DATE=`date +%m%d%Y-%H%M%S`
LOGS=${BaseDir}/../logs
PROPERTIES="${BaseDir}/../properties"
EAP_Scripts=${BaseDir};

application_properties_file="$PROPERTIES/fuse-applications.properties"
install_properties_file="$PROPERTIES/global-fuse-install.properties"

# Source the properties
. $install_properties_file

# Source the functions
. $BaseDir/fuse-functions.sh

trap bashtrap EXIT
bashtrap(){
  
  kill $tailpid    
  kill $greppid      
  	
  exit;
  
}

# Logging
logFile=$LOGS/fuse-menu-${DATE}.log
cat /dev/null > $logFile
tail -f $logFile | grep -v "presented unverified key:" &
greppid=$!
tailpid=$(($greppid-1))
exec >> $logFile
exec 2>&1

checkIfFuseRunning
checkIfFabricCreated
chooseApplication
chooseEnvironment

mainTitle="\E[0;33;42m\033[1m#### MAIN MENU - $chosen_application - $chosen_environment ####\033[0m"
echo -e "\n${mainTitle}\n"
select root_menu in "installApp" "removeApp" "administration" "changeApplication" "changeEnvironment" "Exit"
do
    echo "$root_menu";
    case $root_menu in
    "installApp")
	installApp
	REPLY=""
	echo -e "\n${mainTitle}\n"
	;;
    "removeApp")
	removeApp
	REPLY=""
	echo -e "\n${mainTitle}\n"
	;;
    "administration")
    
	# Make sure there are containers in the environment
	getAllContainerList
	number_containers=${#container_array[@]}
	if [ $number_containers -lt 1 ]; then
	  echo "Error, no containers (instances) installed for application $chosen_application in environment $chosen_environment. Use installApp to install first."
	else
	  admin_title="\E[0;33;41m\033[1m#### Main Menu - $chosen_application - $chosen_environment > Administration ####\033[0m"
	  echo -e "\n${admin_title}\n"
	  select admin_menu in "sshToInstanceUser" "instanceUpgrade" "instanceRollback" "startInstance" "stopInstance" "addProfile" "removeProfile" "environmentInfo" "instanceStatus" "camel" "activeMQStats" "threadDump" "instanceConnect" "rootMenu"
	  do
	    echo "$admin_menu";
	    case $admin_menu in	    
	    "sshToInstanceUser")
		  sshToInstanceUser
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;	
	      "instanceUpgrade")
		  instanceUpgrade
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;	
	      "instanceRollback")
		  instanceRollback
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;
	      "startInstance")
		  startInstance
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;	
	      "stopInstance")
		  stopInstance
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;		
	      "addProfile")
		  addProfile
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;
	      "environmentInfo")
		  environmentInfo
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;
	      "removeProfile")
		  removeProfile
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;	
	      "instanceStatus")
		  instanceStatus
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;		
	      "camel")
		camel_title="\E[0;33;44m\033[1m#### Main Menu - $chosen_application - $chosen_environment > Administration > Camel ####\033[0m"
		echo -e "\n${camel_title}\n"	    
		select camel_menu in "camelRouteStart" "camelRouteStop" "camelRouteInfo" "backToAdminMenu"
		do
		  echo "$camel_menu";
		  case $camel_menu in		    
		  "camelRouteStart")
		      camelRouteStart
		      REPLY=""
		      echo -e "\n${camel_title}\n"
		      ;;	
		  "camelRouteStop")
		      camelRouteStop
		      REPLY=""
		      echo -e "\n${camel_title}\n"
		      ;;
		  "camelRouteInfo")
		      camelRouteInfo
		      REPLY=""
		      echo -e "\n${camel_title}\n"
		      ;;  
		  "backToAdminMenu")
		      break;
		      ;;		  
		  *)
		      echo "That is not a valid choice!  Input a number."
		      ;;			    
		  esac	  
		done	
		REPLY=""
		echo -e "\n${admin_title}\n"
		;;
	      "activeMQStats")
		  activeMQStats
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;	
	      "threadDump")
		  threadDump
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;			
	      "instanceConnect")
		  instanceConnect
		  REPLY=""
		  echo -e "\n${admin_title}\n"
		  ;;	
	 "rootMenu")
	      break;
	      ;;
	  *)
	      echo "That is not a valid choice!  Input a number."
	      ;;	
	  esac	  
	done		  
	fi
	REPLY=""
	echo -e "\n${mainTitle}\n"
	;;	
	
     "changeApplication")
	chooseApplication
	chooseEnvironment
	mainTitle="\E[0;33;42m\033[1m#### MAIN MENU - $chosen_application - $chosen_environment ####\033[0m"
	REPLY=""
	echo -e "\n${mainTitle}\n"
	;;
    "changeEnvironment")
	chooseEnvironment
	mainTitle="\E[0;33;42m\033[1m#### MAIN MENU - $chosen_application - $chosen_environment ####\033[0m"
	REPLY=""
	echo -e "\n${mainTitle}\n"
	;;
    "Exit")
	break;
	;;
    *)
	echo "That is not a valid choice!  Input a number."
	;;	
    esac
done