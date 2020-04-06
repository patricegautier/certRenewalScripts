#!/bin/bash
#set -x

usage()
{
    echo "---------- Invoked: "
    echo ${COMMAND} ${FULLCOMMAND}
    echo "----------"
	echo "Usage "${0}" -t ck|udmp|pihole|container|compose|unms|pihole [-1] [-f] [-k key] [-c containerName] [-d path] <fqdn>"
	echo "  -t:	device type, cloud key, UDMP, pihole or container"
	echo "  -1:  first run, will install acme.sh. -k key must be present to provide the Gandi Live DNS key"
	echo "  -f: force renewal of the cert"
    echo "  -k: specify the Gandi Live DNS Key"
    echo "  -c: container name to install certs for and restart"
    echo "  -d: the directory to install the container certs into, which must be in a docker volume"
    echo "  -o: the directory which contains the docker-compose.yml for type compose"
    echo "  -h: usage and list of default targets"
    echo "  -s: use Let's encrypt's staging environment"
    echo ""
    echo "Return 0 if credentials were updated and the container restarted, 1 if failure, 2 if nothing was changed"
	exit 1
}


COMMAND=$0
FULLCOMMAND=$*

unset FORCE
FIRST_RUN=false
unset DEVICE_TYPE
unset STAGING_OPTION
unset VERBOSE

while getopts 'v1ft:k:c:hd:o:s' o
do
  case $o in
    1) 
    	FIRST_RUN=true 
    	GANDI_LIVEDNS_KEY=${OPTARG}
    	;;
    f) FORCE="--force" ;;
    t) DEVICE_TYPE=${OPTARG} ;;
    k) GANDI_LIVEDNS_KEY=${OPTARG} ;;
    c) CONTAINER_NAME=${OPTARG} ;;
    d) CONTAINER_DIRECTORY=${OPTARG} ;;
    o) COMPOSE_DIRECTORY=${OPTARG} ;;
    h) usage ;;
    v) VERBOSE="t" ;;
    s) STAGING_OPTION="--staging" ;;
  esac
done

shift $((OPTIND-1))

USERATHOST=$1
DOMAIN=$(echo ${USERATHOST} | cut -d"@" -f2)


if [ -z "$DOMAIN" ]; then
    echo "Missing Domain Name in "${USERATHOST}
	usage;
fi

if ! [[ "$DOMAIN" =~ "." ]]; then
    echo "Domain must be full qualified: "${DOMAIN}
    usage;
fi




if [ -z ${DEVICE_TYPE} ]; then
	usage;
fi


BASE=${HOME}/.acme.sh


# First time installation
# assumes acme.sh is in the default location ~/.acme.sh

if  ! [ -e  ${BASE}/acme.sh ]; then   # acme.sh is not installed
	if ! ${FIRST_RUN}; then
		echo "*** Please run updateRemoteCerts.sh with -1 -k <gandiKey> to install and set up acme.sh"
		exit 1;
	else
		echo "Installing acme.sh"
        if [ -z ${GANDI_LIVEDNS_KEY} ]; then
            echo "*** First run and no Gandi Key specified"
            exit 1;
        fi
		curl https://get.acme.sh | sh
        if ! [ -f ${BASE}/acme.sh ]; then
            echo "** ACME Install Failed"
            exit 1
        fi
	fi
fi

export GANDI_LIVEDNS_KEY


if ! [[ -z ${VERBOSE} ]]; then
    echo ${BASE}/acme.sh --upgrade
fi
${BASE}/acme.sh --upgrade > /dev/null


if ! [[ -z ${VERBOSE} ]]; then
    echo ${BASE}/acme.sh ${STAGING_OPTION}--issue --dns dns_gandi_livedns -d  ${DOMAIN} ${FORCE}
fi
${BASE}/acme.sh ${STAGING_OPTION} --issue --dns dns_gandi_livedns -d  ${DOMAIN} ${FORCE}


DT=`date +"%m-%d-%Y-%T"`

#unifi devices

if [[ ${DEVICE_TYPE} == "ck" ]]; then

	UDMP_BASE="/data/unifi-core/config"
	UNIFI_BASE="/etc/ssl/private"
	unset BASE_FOUND


	if [[ ${DEVICE_TYPE} == "udmp" ]] && ! [ -d ${UDMP_BASE} ]; then
		echo "-t udmp specified, but "${UDMP_BASE}" does not exist"
		exit 1;
	fi

	if [[ ${DEVICE_TYPE} == "ck" ]] && ! [ -d ${UNIFI_BASE} ]; then
		echo "-t ck specified, but "${UNIFI_BASE}" does not exist"
		exit 1;
	fi


	if [ -d ${UDMP_BASE} ]; then
	
		CERT_BASE=${UDMP_BASE}
		KEY_TYPE="UDMP keys"
		CRT_FILE="unifi-core.crt"
		KEY_FILE="unifi-core.key"
		BASE_FOUND=true;

	elif [ -d ${UNIFI_BASE} ]; then

		CERT_BASE=${UNIFI_BASE}
		KEY_TYPE="CloudKey keys"
		CRT_FILE="cloudkey.crt"
		KEY_FILE="cloudkey.key"
		BASE_FOUND=true;

	fi

	if [ ${BASE_FOUND} ]; then

		echo Installing ${KEY_TYPE}


		if [ -f ${CERT_BASE}/${CRT_FILE} ]; then
			sudo mv ${CERT_BASE}/${CRT_FILE} ${CERT_BASE}/${CRT_FILE}.${DT}
		fi

		sudo openssl x509 -in ${BASE}/${DOMAIN}/${DOMAIN}.cer -out ${CERT_BASE}/${CRT_FILE}
	
	
		if [ -f ${CERT_BASE}/${KEY_FILE} ]; then
			sudo mv ${CERT_BASE}/${KEY_FILE} ${CERT_BASE}/${KEY_FILE}.${DT}
		fi

		sudo openssl rsa -in ${BASE}/${DOMAIN}/${DOMAIN}.key -out ${CERT_BASE}/${KEY_FILE}

	else
	
		echo "No cert base found"
		exit 1;
		
	fi



	
	if [[ ${DEVICE_TYPE} == "ck" ]]; then
	
		NGINX=`which nginx`

		if [ ! -z ${NGINX} ]; then
			echo "Restarting nginx"
			service nginx stop
			service nginx start
		else
			echo "Nginx not installed"
		fi

		# then the keystore used by the java unifi software
		if [ -f "/etc/ssl/private/unifi.keystore.jks" ]; then
			openssl pkcs12 -export -inkey ${BASE}/${DOMAIN}/${DOMAIN}.key -in ${BASE}/${DOMAIN}/fullchain.cer -out fullchain.p12 -name unifi -password pass:unifi

			mv /etc/ssl/private/unifi.keystore.jks /etc/ssl/private/unifi.keystore.jks.${DT}

			keytool -importkeystore -deststoretype pkcs12 -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore /etc/ssl/private/unifi.keystore.jks -srckeystore ./fullchain.p12 -srcstoretype PKCS12 -srcstorepass unifi -alias unifi -noprompt
			rm fullchain.p12
		else
			echo "Skipping Unifi Java Keys"
		fi

		# only if unifi is running!
		UNIFI_STATUS=`/usr/sbin/service unifi status 2>&1| grep Active | awk '{print $2}'`
		UNIFI_STATUS=${UNIFI_STATUS,,}
		if  [ "$UNIFI_STATUS" = "active" ] && [ ! -d ${UDMP_BASE} ]; then
			echo "Restarting Unifi Service"
			service unifi stop
			service unifi start
		else
				echo "Skipping Unifi CK Service"
		fi


		# Management Portal
		PORTAL_STATUS=`service unifi-management-portal status 2>&1| grep Active | awk '{print $2}'`
		PORTAL_STATUS=${PORTAL_STATUS,,}
		if  [ "$PORTAL_STATUS" = "active" ]; then
			echo "Restarting Management Portal"
			service unifi-management-portal stop
			service unifi-management-portal start
		else
				echo "Skipping CK Management Portal"
		fi


		## Protect - right now the cloud key needs to be restarted to take the new cert -- there has to be a better way
		PROTECT_BASE=/srv/unifi-protect/
		if [ -d "$PROTECT_BASE" ]; then
			echo "You need to restart " $1 " to get Protect to use new Cert"
			echo "Do you wish to reboot now?"
			select yn in "Yes" "No"; do
				case $yn in
				  Yes ) sudo reboot; break;;
				  No ) exit;;
				esac
			done	
		else
			echo "Skipping Protect"
		fi

		
	fi



	
fi # end Unifi devices


# Synology certs
# to enable password-less sudo, had to add to /etc/sudoers
# patrice  ALL=(ALL) NOPASSWD: ALL


if  [[ ${DEVICE_TYPE} == "syn" ]]; then

    SYN_BASE=/usr/syno/etc/certificate
    
    FQDN_BASE=${SYN_BASE}/system/FQDN
    DEFAULT_BASE=${SYN_BASE}/system/default
    SMB_BASE=${SYN_BASE}/smbftpd/ftpd/
    
    echo "Installing Synology Certificates"
    
    sudo openssl x509 -in ${BASE}/${DOMAIN}/${DOMAIN}.cer -out ${FQDN_BASE}/cert.pem || exit 1
    sudo openssl rsa -in ${BASE}/${DOMAIN}/${DOMAIN}.key -out ${FQDN_BASE}/privkey.pem || exit 1
    sudo cp ${FQDN_BASE}/cert.pem ${FQDN_BASE}/fullchain.pem || exit 1
        
    sudo chmod  u=r,g=,o=   ${FQDN_BASE}/cert.pem || exit 1
    sudo chmod  u=r,g=,o=   ${FQDN_BASE}/privkey.pem || exit 1
    sudo chmod  u=r,g=,o=   ${FQDN_BASE}/fullchain.pem || exit 1
    
    sudo cp ${FQDN_BASE}/cert.pem ${DEFAULT_BASE} || exit 1
    sudo cp ${FQDN_BASE}/privkey.pem ${DEFAULT_BASE} || exit 1
    sudo cp ${FQDN_BASE}/fullchain.pem ${DEFAULT_BASE} || exit 1

    sudo cp ${FQDN_BASE}/cert.pem ${SMB_BASE} || exit 1
    sudo cp ${FQDN_BASE}/privkey.pem ${SMB_BASE} || exit 1
    sudo cp ${FQDN_BASE}/fullchain.pem ${SMB_BASE} || exit 1

    sudo nginx -s reload || exit 1

fi




if  [[ ${DEVICE_TYPE} == "container" ]]  || [[ ${DEVICE_TYPE} == "compose" ]] || [[ ${DEVICE_TYPE} == "pihole" ]] || [[ ${DEVICE_TYPE} == "udmp" ]]; then
    
    unset DIFF
    
    
    if [[ ${DEVICE_TYPE} == "pihole" ]]; then   # piholes refer directly to the .acme.sh directory
        CERT_BASE=${BASE}/${DOMAIN}
    else
        CERT_BASE=${CONTAINER_DIRECTORY}
    fi
        
    if [ -z "$CERT_BASE" ]; then
        echo "Missing Target Directory"
        usage;
    fi

    if ! [[ -z ${VERBOSE} ]]; then
        echo "Installing .key, .crt, .pem in "${CERT_BASE}
    fi
    
    if ! [ -f ${CERT_BASE}/${DOMAIN}.key ] || [ `cmp -s ${BASE}/${DOMAIN}/${DOMAIN}.key ${CERT_BASE}/${DOMAIN}.key` ]; then
        sudo openssl rsa -in ${BASE}/${DOMAIN}/${DOMAIN}.key -out ${CERT_BASE}/${DOMAIN}.key || exit 1
        DIFF=1
    elif ! [[ -z ${VERBOSE} ]]; then
        echo ${CERT_BASE}/${DOMAIN}.key" unchanged"
    fi

    if ! [ -f ${CERT_BASE}/${DOMAIN}.crt ] || [ `cmp -s ${BASE}/${DOMAIN}/${DOMAIN}.crt ${CERT_BASE}/${DOMAIN}.crt` ]; then
        sudo openssl rsa -in ${BASE}/${DOMAIN}/${DOMAIN}.crt -out ${CERT_BASE}/${DOMAIN}.crt || exit 1
        DIFF=1
    elif ! [[ -z ${VERBOSE} ]]; then
        echo ${CERT_BASE}/${DOMAIN}.crt" unchanged"
    fi

    # Note can't use regular > or >> because those redirections will not inherit the sudo part
    sudo cat ${CERT_BASE}/${DOMAIN}.key ${CERT_BASE}/${DOMAIN}.crt | sudo tee ${CERT_BASE}/tmp.pem >/dev/null || exit 1
    if ! [ -f ${CERT_BASE}/${DOMAIN}.pem ] || [ `cmp -s ${CERT_BASE}/tmp.pem ${CERT_BASE}/${DOMAIN}.pem` ]; then
        #sudo rm -f ${CERT_BASE}/${DOMAIN}.pem  || exit 1
        sudo mv ${CERT_BASE}/tmp.pem ${CERT_BASE}/${DOMAIN}.pem || exit 1
        DIFF=1
    else
        sudo rm -f ${CERT_BASE}/tmp.pem || exit 1
    fi


    if ! [[ -z "${DIFF}" ]]; then # Restart

        if  [[ ${DEVICE_TYPE} == "container" ]]; then

            if [ -z "$CONTAINER_NAME" ]; then
                echo "Missing Container Name"
                usage;
            fi
            echo "Restarting container "${CONTAINER_NAME}
            sudo /usr/local/bin/docker restart ${CONTAINER_NAME} || exit 1
            
        elif [[ ${DEVICE_TYPE} == "compose" ]]; then
        
            if [ -z "$COMPOSE_DIRECTORY" ]; then
                echo "Missing docker compose directory"
                usage;
            fi
            
            echo "Restarting composed container from "${COMPOSE_DIRECTORY}
            cd ${COMPOSE_DIRECTORY} && docker-compose down && docker-compose up -d || exit 1
            
        elif [[ ${DEVICE_TYPE} == "pihole" ]]; then
        
            sudo service lighttpd restart || exit 1

        fi
        
    else
        echo "No credential changed -- Skipping restart"
        exit 2
    fi

fi

