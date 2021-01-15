#!/bin/bash
# set -x

usage()
{
	echo "Usage "${0}" [-d] [-i privateKeyPath] [-s <fileName>] [-u user] user@targetMachine"
	echo "-i specify private public key pair"
	echo "-s use sshpass with given password file. Will ask for the password if sshpass is not installed"
	echo "-d disabled strict host key checking with SSH option StrictHostKeyChecking=no"
	echo "-b for dropbear (used in protect cameras) additionally copy ~/.ssh/authorized_keys to /var/etc/dropbear"
	echo "-u run the command as <user>"
	exit 2
}



STRICT=""
unset DROPBEAR
unset SUDO_USER

while getopts 'i:s:dbu:' OPT
do
  case $OPT in
    i) PRIVKEY_PATH=${OPTARG} ;;
    s) SSH_PASS_FILE=${OPTARG} ;;
    d) STRICT="-o StrictHostKeyChecking=no" ;;
    b) DROPBEAR=true ;;
    u) SUDO_USER="sudo -u "${OPTARG} ;;
  esac
done

shift $((OPTIND-1))


TARGET=$@


if [[ -z ${TARGET} ]]; then
	usage
fi


if [[ -z ${PRIVKEY_PATH} ]]; then
   	PRIVKEY_PATH=${HOME}"/.ssh/id_rsa"
fi

PUBKEY_PATH=${PRIVKEY_PATH}".pub"
PUBKEY=$(<${PUBKEY_PATH}) || exit 1;

if [[ -z "${PUBKEY}" ]]; then
	echo "Could not read public key at "${PUBKEY_PATH}
	exit 1
fi



${SUDO_USER} ssh -i ${PRIVKEY_PATH} -q -o "BatchMode yes" ${TARGET} true
PUBKEY_OK=$?
SSHPASS=`which sshpass`

if [ ${PUBKEY_OK} != '0'  ]; then
	echo Need to update public key for ${TARGET}
	unset DROPBEAR_CMD
   	if ! [[ -z ${DROPBEAR} ]]; then
	   	DROPBEAR_CMD=" && cp .ssh/authorized_keys /var/etc/dropbear/"
   	fi
	if [[ -z ${SSH_PASS_FILE} ]] || ! [[ -e ${SSH_PASS_FILE} ]] || [[ -z ${SSHPASS} ]]; then
	   	${SUDO_USER} ssh ${STRICT} ${TARGET} "mkdir -p .ssh && echo '${PUBKEY}' >> .ssh/authorized_keys ${DROPBEAR_CMD}" || exit 1;
	else
	   	${SUDO_USER} sshpass -f ${SSH_PASS_FILE} ssh ${STRICT} ${TARGET} "mkdir -p .ssh && echo '${PUBKEY}' >> .ssh/authorized_keys ${DROPBEAR_CMD}" || exit 1;		
	fi
fi

#ssh-copy-id ${TARGET}  > /dev/null



