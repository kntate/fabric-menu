BaseDir=${0%/*}
DATE=`date +%m%d%Y-%H%M%S`
LOGS=${BaseDir}/../logs
EAP_Scripts=${BaseDir};

# Source the properties
. $BaseDir/../properties/fuse-install.properties

# Source the functions
. $BaseDir/fuse-functions.sh

trap bashtrap EXIT
bashtrap(){
  
  kill $tailpid    
  kill $greppid      
  	
  exit;
  
}

# Logging
logFile=$LOGS/fabric-menu-${DATE}.log
cat /dev/null > $logFile
tail -f $logFile | grep -v "presented unverified key:" &
greppid=$!
tailpid=$(($greppid-1))
exec >> $logFile
exec 2>&1

checkIfFuseRunning
checkIfFabricCreated

# Kill the script if there is an error
set -e

mainTitle="\E[0;33;42m\033[1m#### MAIN MENU ####\033[0m"
echo -e "\n${mainTitle}\n"
select root_menu in "installEnsemble" "installApp" "removeApp" "administration" "Exit"
do
    echo "$root_menu";
    case $root_menu in
    "installEnsemble")
	installEnsemble
	REPLY=""
	echo -e "\n${mainTitle}\n"
	;;
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
	admin_title="\E[0;33;41m\033[1m#### Main Menu  > Administration ####\033[0m"
	echo -e "\n${admin_title}\n"
	select admin_menu in "sshToContainer" "containerUpgrade" "containerRollback" "startContainer" "stopContainer" "addProfile" "removeProfile" "environmentInfo" "containerStatus" "camel" "activeMQStats" "threadDump" "containerConnect" "rootMenu"
	do
	  echo "$admin_menu";
	  case $admin_menu in	    
	  "sshToContainer")
		sshToContainer
		REPLY=""
		echo -e "\n${admin_title}\n"
		;;	
	    "containerUpgrade")
		containerUpgrade
		REPLY=""
		echo -e "\n${admin_title}\n"
		;;	
	    "containerRollback")
		containerRollback
		REPLY=""
		echo -e "\n${admin_title}\n"
		;;
	    "startContainer")
		startContainer
		REPLY=""
		echo -e "\n${admin_title}\n"
		;;	
	    "stopContainer")
		stopContainer
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
	    "containerStatus")
		containerStatus
		REPLY=""
		echo -e "\n${admin_title}\n"
		;;		
	    "camel")
	      camel_title="\E[0;33;44m\033[1m#### Main Menu  > Administration > Camel ####\033[0m"
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
	    "containerConnect")
		containerConnect
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