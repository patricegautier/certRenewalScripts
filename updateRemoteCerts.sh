#!/bin/bash
#set -x

usage()
{
	echo "Usage "${0}" [-1] [-f] [-k gandiLiveDNSKey] [-h] [-s] [ <target>* | <name>* ]"
    echo ""
	echo "  -1: first run, will install acme.sh on the remote machine"
	echo "  -f: force renewal of the cert"
	echo "  -k: your Gandi LiveDNS key - defaults to the contents of ~/.ssh/gandiLiveDNS.key. Required if -1 specified"
    echo "  -c: container name to install certs into. Assumes nginx install in that container in /etc/nginx"
    echo "  -h: usage and lists the default targets"
    echo "  -v: verbose output"
    echo "  -s: using let's encrypt staging to avoid running into quotas"
    echo "  -l: list the available device names from the list of targets"
    echo ""
	echo "  targets: defaults to the contents of ~/.ssh/remoteCertHosts.txt"
    echo "    Possible formats are:"
    echo "       <name>:apache2:<username@FQDN> for apache setup"
    echo "       <name>:unms:<username@FQDN>: UNMS container install"
    echo "       <name>:pihole:<username@FQDN> for pihole on rasperry pi"
    echo "       <name>:ck:<username@FQDN> for Cloud Keys"
    echo "       <name>:syn:<username@FQDN> for Synology boxes"
    echo "       <name>:nvr4:<username@FQDN> for Unifi NVR4 protect servers"
    echo "       <name>:container:<containName>:<targetDirectory>:<username@FQDN> for generic container targets"
    echo "          The target dir must be in a docker volume"
    echo "  name: lookup devices definitions by name in ~/.ssh/remoteCertHosts.txt"
    echo ""
	exit 1
}


SCRIPT_DIR=$(dirname "$0")


REMOTE_SCRIPT_NAME="updateLocalCerts.sh"

unset FORCE
unset FIRST_RUN
unset DEVICES
unset GANDI_KEY
unset CONTAINER_OPTION
unset HELP
unset VERBOSE
unset STAGING_OPTION
unset TARGET_DEVICE_NAMES
unset LIST_MODE

while getopts '1fk:hvsl' OPT
do
  case $OPT in
    1) FIRST_RUN="-1" ;;
    f) FORCE="-f" ;;
    k) GANDI_KEY=${OPTARG} ;;
    h) HELP="t" ;;
    v) VERBOSE="-v" ;;
    s) STAGING_OPTION="-s" ;;
    l) LIST_MODE="t" ;;
  esac
done

shift $((OPTIND-1))
DEVICES_FROM_CMDLINE=$@

if ! [[ -z ${HELP} ]]; then
    usage
fi

# read config file
HOSTS_PATH=${HOME}"/.ssh/remoteCertHosts.txt"
if [ -f ${HOSTS_PATH} ]; then
    DEVICES_FROM_FILE=`cat ${HOSTS_PATH} | grep ^[^#]`
fi


if [ -z "$DEVICES_FROM_CMDLINE" ]; then #nothing on the command line
    DEVICES=${DEVICES_FROM_FILE}
else
    if  [[ "$DEVICES_FROM_CMDLINE" =~ ":" ]]; then  # it's a list of targets
        DEVICES=${DEVICES_FROM_CMDLINE}
    else #it's a list of names
        DEVICES=${DEVICES_FROM_FILE}
        TARGET_DEVICE_NAMES=${DEVICES_FROM_CMDLINE}
    fi

fi
    
if [ -z "$DEVICES" ]; then
    echo "** No target or name specified and could not read default list from "${HOSTS_PATH}
    usage
fi

if [ ! -z ${VERBOSE} ]; then
    echo ""
    echo "Device(s):  "
    for k in ${DEVICES}
    do
        echo "   "${k}
    done
    echo ""
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



for k in ${DEVICES}
do

    unset DEVICE_TYPE
    unset CONTAINER_NAME
    unset TARGET_DIR
    unset CONTAINER_OPTION
    unset COMPOSE_OPTION
    REMOTE_SCRIPT_DIR=/tmp
    unset DEVICE_TYPE
    unset DEVICE_NAME

    if ! [[ -z "$k" ]] && ! [[ "$k" =~ ^\#.* ]]; then   # not a blank line and not a comment

        if ! [[ "$k" =~ ":" ]]; then   # Missing name
            echo "Missing name in "$k
            usage
        else
            DEVICE_NAME=`echo "$k" | awk -F':' '{print $1}'`
        fi

        if ! [[ -z ${LIST_MODE} ]]; then
            echo ${DEVICE_NAME}
        else
            if [[ -z ${TARGET_DEVICE_NAMES} ]] || [[ ${TARGET_DEVICE_NAMES} =~ ${DEVICE_NAME} ]]; then

                echo "-------------- Processing "${DEVICE_NAME}

                if [[ "$k" =~ ":" ]]; then   # type was explicitly specified
                    DEVICE_TYPE=`echo "$k" | awk -F':' '{print $2}'`

                    if [[ ${DEVICE_TYPE} == "container" ]]; then

                        CONTAINER_NAME=`echo "$k" | awk -F':' '{print $3}'`
                        TARGET_DIR=`echo "$k" | awk -F':' '{print $4}'`
                        CONTAINER_OPTION="-c "${CONTAINER_NAME}" -d "${TARGET_DIR}
                        k=`echo "$k" | awk -F':' '{print $5}'`
                        if ! [[ -z ${VERBOSE} ]]; then
                            echo "Container name: "${CONTAINER_NAME}
                            echo "Target directory: "${TARGET_DIR}
                        fi

                    elif [[ ${DEVICE_TYPE} == "compose" ]]; then

                        COMPOSE_DIR=`echo "$k" | awk -F':' '{print $3}'`
                        TARGET_DIR=`echo "$k" | awk -F':' '{print $4}'`
                        COMPOSE_OPTION="-o "${COMPOSE_DIR}" -d "${TARGET_DIR}
                        k=`echo "$k" | awk -F':' '{print $5}'`
                        if ! [[ -z ${VERBOSE} ]]; then
                            echo "Container name: "${CONTAINER_NAME}
                            echo "Target directory: "${TARGET_DIR}
                        fi
                        
                    else # unms, udmp and pihole
                        k=`echo "$k" | awk -F':' '{print $3}'`
                        if [[ ${DEVICE_TYPE} == "udmp" ]]; then
                            #Those directories are hardcoded on a UDMP
                            REMOTE_SCRIPT_DIR="/mnt/data/unifi-os"
                            CONTAINER_OPTION="-c unifi-os -d /data/unifi-core/config"
                        fi
                    fi
                else
                    echo "Missing type in "$k
                    usage
                fi


                if ! [[ "$k" =~ "@" ]]; then
                    echo "** Missing user name in" ${k}
                    usage
                fi
             
                if ! [[ "$k" =~ "." ]]; then
                    echo "Domain must be fully qualified: "${k}
                    usage;
                fi

                if ! [[ -z ${VERBOSE} ]]; then
                    echo "Device type: "${DEVICE_TYPE}
                fi

                if ! [[ -z ${VERBOSE} ]]; then
                    echo "user@domain: "$k
                fi


             
                
                # Making sure the public key is correctly setuo - you might have to type your password the first time
                ${SCRIPT_DIR}/updatePublicKey.sh ${k} || exit 1;

                # Making sure the acme directory exists
                ssh -o LogLevel=Error  ${k} mkdir -p ${REMOTE_SCRIPT_DIR} || exit 1;
                    
                if ! [[ -z ${VERBOSE} ]]; then
                    echo         scp -o LogLevel=Error  "${SCRIPT_DIR}/${REMOTE_SCRIPT_NAME}" ${k}:${REMOTE_SCRIPT_DIR}/${REMOTE_SCRIPT_NAME}
                fi
                scp -o LogLevel=Error  "${SCRIPT_DIR}/${REMOTE_SCRIPT_NAME}" ${k}:${REMOTE_SCRIPT_DIR}/${REMOTE_SCRIPT_NAME} > /dev/null || exit 1;

                if [[ ${DEVICE_TYPE} == "udmp" ]]; then   #the UDMP is special because you have to run acme.sh inside the container

                    if ! [[ -z ${VERBOSE} ]]; then
                        echo ssh  -o LogLevel=Error ${k} docker exec unifi-os /data/${REMOTE_SCRIPT_NAME} ${VERBOSE} -t ${DEVICE_TYPE} ${FIRST_RUN} ${FORCE} ${CONTAINER_OPTION} ${GANDI_KEY_OPTION} ${COMPOSE_OPTION} ${STAGING_OPTION} ${k}
                    fi

                    ssh  -o LogLevel=Error ${k} docker exec unifi-os /data/${REMOTE_SCRIPT_NAME} ${VERBOSE} -t ${DEVICE_TYPE} ${FIRST_RUN} ${FORCE} ${CONTAINER_OPTION} ${GANDI_KEY_OPTION} ${COMPOSE_OPTION} ${STAGING_OPTION} ${k} 2> /tmp/updateLocalCerts.err
                    
                    SUCCESS=$?
                    
                    if [[ ${SUCCESS} -eq 0 ]]; then
                        #if ! [[ -z ${VERBOSE} ]]; then
                            echo "Restarting unifi-os on "${k}
                        #fi
                        ssh -o LogLevel=Error ${k} unifi-os restart
                    elif [[ ${SUCCESS} -ne 2 ]]; then # 2 only means nothing was changed
                        echo "An error was encountered on the UDMP - it is logged at /tmp/updateLocalCerts.err"
                        exit 1
                    fi
         
                else
                
                    if ! [[ -z ${VERBOSE} ]]; then
                        echo ssh  -o LogLevel=Error ${k} ${REMOTE_SCRIPT_DIR}/${REMOTE_SCRIPT_NAME} ${VERBOSE} -t ${DEVICE_TYPE} ${FIRST_RUN} ${FORCE} ${CONTAINER_OPTION} ${GANDI_KEY_OPTION} ${COMPOSE_OPTION} ${STAGING_OPTION} ${k}
                    fi
                
                    ssh  -o LogLevel=Error ${k} ${REMOTE_SCRIPT_DIR}/${REMOTE_SCRIPT_NAME} ${VERBOSE} -t ${DEVICE_TYPE} ${FIRST_RUN} ${FORCE} ${CONTAINER_OPTION} ${GANDI_KEY_OPTION} ${COMPOSE_OPTION} ${STAGING_OPTION} ${k}
                    
                    SUCCESS=$?
                        
                    if [[ ${SUCCESS} -ne 2 ]] && [[ ${SUCCESS} -ne 0 ]]; then # 2 only means nothing was changed
                    	echo "********************************* "$k" failed"
                        #exit 1 -- keep going
                    fi


                fi
            fi
        fi # end processing device
    fi # end not a comment
done


