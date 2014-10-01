# Kill the script if there is an error
set -e

# Source the functions
. fabric-functions.sh

returnToMenu(){
  echo -e "\n\n"
  REPLY=""
  echo "Make another selection."
}

select menu1 in "installEnsemble" "installApp" "startContainer" "stopContainer" "addProfile" "removeProfile" "containerStatus" "camelRouteStart" "activeMQStats" "containerConnect" "Exit"
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

