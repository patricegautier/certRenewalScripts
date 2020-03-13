#!/bin/bash
#set -x

usage()
{
	echo "Usage "${0}" [-1] [-f] [-k gandiLiveDNSKey] user@hostName*"
	echo "  -1: first run, will install acme.sh on the remote machine"
	echo "  -f: force renewal of the cert"
	echo "  -k: your Gandi LiveDNS key - defaults to the contents of ~/.ssh/gandiLiveDNS.key. Required if -1 specified"
	echo "  user@hostname*: host names must be FQDNs. CK, UDMP or rPi are supported"
	echo "		defaults to the contents of ~/.ssh/remoteCertHosts.txt"
	exit 1
}


#SCRIPT_DIR="/Users/patrice/Library/Mobile Documents/com~apple~CloudDocs/House/Unifi"
SCRIPT_DIR=$(dirname "$0")


REMOTE_SCRIPT_NAME="updateLocalCerts.sh"

unset FORCE
unset FIRST_RUN
unset DEVICES
unset GANDI_KEY

while getopts '1fk:' o
do
  case $o in
    1) 
    	FIRST_RUN="-1" ;;
    f) FORCE="-f" ;;
    k) GANDI_KEY=${OPTARG}
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


if ! [ -z ${FIRST_RUN} ]; then

	if [ -z ${GANDI_KEY} ]; then

		KEY_PATH=${HOME}"/.ssh/gandiLiveDNS.key"
		GANDI_KEY=$(<${KEY_PATH})
		if [ -z "$GANDI_KEY" ]; then
			echo "-1 specified without -k entry and could not read Gandi LiveDNS key from "${KEY_PATH}
			usage
		fi
	fi
	FIRST_RUN="-1 ${GANDI_KEY}"
    	
fi



for k in ${DEVICES}  #simplistic naming scheme to id devices:  ck* is a cloudkey, gw* is a udmp, pi* is a rPi
do
	unset DEVICE_TYPE
	if [[ "$k" =~ "pi" ]]; then
		ACME_DIR=.acme.sh
		DEVICE_TYPE="pi"
	elif [[ "$k" =~ "gw" ]]; then
		ACME_DIR=/mnt/data/unifi-os/
		DEVICE_TYPE="udmp"
	else 
		ACME_DIR=/root/.acme.sh
		DEVICE_TYPE="ck"
	fi
	
	echo "-------------- Processing "${k}
	
	# Making sure the public key is correctly setuo - you might have to type your password the first time
	${SCRIPT_DIR}/updatePublicKey.sh ${k} || exit 1;

	# Making sure the acme directory exists
	ssh ${k} mkdir -p ${ACME_DIR} || exit 1;
		
	scp "${SCRIPT_DIR}/${REMOTE_SCRIPT_NAME}" ${k}:${ACME_DIR}/${REMOTE_SCRIPT_NAME} || exit 1;
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
		ssh ${k} ${ACME_DIR}/${REMOTE_SCRIPT_NAME} -t ${DEVICE_TYPE} ${FIRST_RUN} ${FORCE} ${k} || exit 1;
	fi
done



# Synology renewal
# pi@pi499:~/synology $ ~/.acme.sh/acme.sh --issue --dns dns_gandi_livedns -d  syn99.gautiers.name
# [Wed 25 Dec 15:23:53 PST 2019] Your cert is in  /home/pi/.acme.sh/syn99.gautiers.name/syn99.gautiers.name.cer 
# [Wed 25 Dec 15:23:53 PST 2019] Your cert key is in  /home/pi/.acme.sh/syn99.gautiers.name/syn99.gautiers.name.key 
# [Wed 25 Dec 15:23:53 PST 2019] The intermediate CA cert is in  /home/pi/.acme.sh/syn99.gautiers.name/ca.cer 
# [Wed 25 Dec 15:23:53 PST 2019] And the full chain certs is there:  /home/pi/.acme.sh/syn99.gautiers.name/fullchain.cer 
