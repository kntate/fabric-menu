# Kill the script if there is an error
set -e

BaseDir=${0%/*}
DATE=`date +%m%d%Y-%H%M%S`
LOGS=${BaseDir}/../logs
EAP_Scripts=${BaseDir};

# Source the functions
. $BaseDir/fabric-functions.sh

# Source the properties
. $BaseDir/../properties/container-install.properties


trap bashtrap INT
bashtrap()
{
	kill -9 $tailpid	
	exit;
}

# Logging
logFile=$LOGS/fabric-menu-${DATE}.log
cat /dev/null > $logFile
tail -f $logFile | grep -v "presented unverified key:" &
tailpid=$!
exec >> $logFile
exec 2>&1

returnToMenu(){
  echo -e "\n\n"
  REPLY=""
  echo "Make another selection."
}

select root_menu in "installEnsemble" "installApp" "administration" "Exit"
do
    echo "$root_menu";
    case $root_menu in
    "installEnsemble")
	installEnsemble
	returnToMenu
	;;
    "installApp")
	installApp
	returnToMenu
	;;
    "administration")
	select admin_menu in "sshToContainer" "containerUpgrade" "containerRollback" "startContainer" "stopContainer" "addProfile" "removeProfile" "environmentInfo" "containerStatus" "camelRouteStart" "activeMQStats" "containerConnect" "rootMenu"
	do
	  echo "$admin_menu";
	  case $admin_menu in	    
	  "sshToContainer")
		sshToContainer
		returnToMenu
		;;	
	    "containerUpgrade")
		containerUpgrade
		returnToMenu
		;;	
	    "containerRollback")
		containerRollback
		returnToMenu
		;;
	    "startContainer")
		startContainer
		returnToMenu
		;;	
	    "stopContainer")
		stopContainer
		returnToMenu
		;;		
	    "addProfile")
		addProfile
		returnToMenu
		;;
	    "environmentInfo")
		environmentInfo
		returnToMenu
		;;
	    "removeProfile")
		removeProfile
		returnToMenu
		;;	
	    "containerStatus")
		containerStatus
		returnToMenu
		;;
	    "camelRouteStart")
		camelRouteStart
		returnToMenu
		;;	
	    "activeMQStats")
		activeMQStats
		returnToMenu
		;;	
	    "containerConnect")
		containerConnect
		returnToMenu
		;;			  
	  "rootMenu")
	      break;
	      ;;
	  *)
	      echo "That is not a valid choice!  Input a number."
	      ;;	
	  esac	  
	done
	returnToMenu
	;;	
 
    "Exit")
	break;
	;;
    *)
	echo "That is not a valid choice!  Input a number."
	;;	
    esac
done

