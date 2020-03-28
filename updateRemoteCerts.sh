#!/bin/bash
#set -x

usage()
{
	echo "Usage "${0}" [-1] [-f] [-k gandiLiveDNSKey] user@hostName.FQDN*"
	echo "  -1: first run, will install acme.sh on the remote machine"
	echo "  -f: force renewal of the cert"
	echo "  -k: your Gandi LiveDNS key - defaults to the contents of ~/.ssh/gandiLiveDNS.key. Required if -1 specified"
	echo "  user@hostname*: host names must be FQDNs. CK, UDMP or rPi are supported"
	echo "		defaults to the contents of ~/.ssh/remoteCertHosts.txt"
	exit 1
}


SCRIPT_DIR=$(dirname "$0")


REMOTE_SCRIPT_NAME="updateLocalCerts.sh"

unset FORCE
unset FIRST_RUN
unset DEVICES
unset GANDI_KEY

while getopts '1fk:' o
do
  case $o in
    1) FIRST_RUN="-1" ;;
    f) FORCE="-f" ;;
    k) GANDI_KEY=${OPTARG} ;;
  esac
done

shift $((OPTIND-1))
DEVICES=$@



if [ -z "$DEVICES" ]; then
	HOSTS_PATH=${HOME}"/.ssh/remoteCertHosts.txt"
	if [ -f ${HOSTS_PATH} ]; then
		DEVICES=$(<${HOSTS_PATH})
	fi
	if [ -z "$DEVICES" ]; then
		echo "** No host name specified and could not read default devices list from "${HOSTS_PATH}
		usage
	fi
	
fi


if [ -z ${GANDI_KEY} ] && ! [ -z ${FIRST_RUN} ]; then
    KEY_PATH=${HOME}"/.ssh/gandiLiveDNS.key"
    GANDI_KEY=$(<${KEY_PATH})
    if [ -z "$GANDI_KEY" ] && ! [ -z ${FIRST_RUN} ]; then
        echo "-1 specified without -k entry and could not read Gandi LiveDNS key from "${KEY_PATH}
        usage
    fi
fi

unset GANDI_KEY_OPTION
if ! [ -z ${GANDI_KEY} ]; then
    GANDI_KEY_OPTION="-k "${GANDI_KEY}
fi

REMOTE_SCRIPT_DIR=/tmp/


for k in ${DEVICES}  #simplistic naming scheme to id devices:  ck* is a cloudkey, gw* is a udmp, pi* is a rPi, syn* is a synology box
do
	echo "-------------- Processing "${k}

	unset DEVICE_TYPE
	if [[ "$k" =~ "pi" ]]; then
		#REMOTE_SCRIPT_DIR=.acme.sh
		DEVICE_TYPE="pi"
	elif [[ "$k" =~ "gw" ]]; then
		#REMOTE_SCRIPT_DIR=/mnt/data/unifi-os/
		DEVICE_TYPE="udmp"
	elif [[ "$k" =~ "ck" ]]; then
		#REMOTE_SCRIPT_DIR=/root/.acme.sh
		DEVICE_TYPE="ck"
    elif [[ "$k" =~ "syn" ]]; then
        DEVICE_TYPE="syn"
	fi
	
	if ! [[ "$k" =~ "@" ]]; then 
		echo "** Missing user name in" ${k}
		usage
	fi
 
    if ! [[ "$k" =~ "." ]]; then
        echo "Domain must be full qualified: "${k}
        usage;
    fi


 
	
	# Making sure the public key is correctly setuo - you might have to type your password the first time
	${SCRIPT_DIR}/updatePublicKey.sh ${k} || exit 1;

	# Making sure the acme directory exists
	ssh ${k} mkdir -p ${REMOTE_SCRIPT_DIR} || exit 1;
		
	scp "${SCRIPT_DIR}/${REMOTE_SCRIPT_NAME}" ${k}:${REMOTE_SCRIPT_DIR}/${REMOTE_SCRIPT_NAME} > /dev/null || exit 1;
	if [[ ${DEVICE_TYPE} == "udmp" ]]; then
		echo "***** Need Manual Input"
		echo
		echo "1/ ssh into the UDMP with"
		echo "  ssh "${k}
		echo
		echo "2/ start the unifi container with"
		echo "  unifi-os shell"
		echo
		echo "3/ and then in the container's shell run:"
		echo "  /data/updateLocalCerts.sh -t udmp "${FIRST_RUN} ${FORCE} ${k}
		echo
		echo "4/ after script completes, in the UDMP's main OS:"
		echo "  unifi-os restart"
		echo
	else
		ssh  -o LogLevel=Error ${k} ${REMOTE_SCRIPT_DIR}/${REMOTE_SCRIPT_NAME} -t ${DEVICE_TYPE} ${FIRST_RUN} ${FORCE} ${GANDI_KEY_OPTION} ${k} || exit 1;
	fi
done


