# Kill the script if there is an error
set -e

BaseDir=${0%/*}
DATE=`date +%m%d%Y-%H%M%S`
LOGS=${BaseDir}/../logs
EAP_Scripts=${BaseDir};

# Source the functions
. $BaseDir/fabric-functions.sh

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

select menu1 in "installEnsemble" "installApp" "containerUpgrade" "startContainer" "stopContainer" "addProfile" "removeProfile" "containerStatus" "camelRouteStart" "activeMQStats" "containerConnect" "Exit"
do
    echo "$menu1";
    case $menu1 in
    "installEnsemble")
	installEnsemble
	returnToMenu
	;;
    "installApp")
	installApp
	returnToMenu
	;;	
    "containerUpgrade")
	containerUpgrade
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
    "Exit")
	break;
	;;
    *)
	echo "That is not a valid choice!  Input a number."
	;;	
    esac
done

