#!/bin/bash
#set -x

usage()
{
	echo "Usage "${0}" [-i privateKeyPath] user@targetMachine"
    echo "  returns "
	exit 2
}





while getopts 'i:' OPT
do
  case $OPT in
    i) PRIVKEY_PATH=${OPTARG} ;;
  esac
done

shift $((OPTIND-1))


TARGET=$@


if [ -z ${TARGET} ]; then
	usage
fi


if [ -z ${PRIVKEY_PATH} ]; then
   	PRIVKEY_PATH=${HOME}"/.ssh/id_rsa"
fi

PUBKEY_PATH=${PRIVKEY_PATH}".pub"
PUBKEY=$(<${PUBKEY_PATH}) || exit 1;

if [ -z "${PUBKEY}" ]; then
	echo "Could not read public key at "${PUBKEY_PATH}
	exit 1
fi



ssh -i ${PRIVKEY_PATH} -q -o "BatchMode yes" ${TARGET} true
PUBKEY_OK=$?

if [ ${PUBKEY_OK} != '0'  ]; then
	echo "Need to update public key for " ${TARGET}

   	ssh -i ${PRIVKEY_PATH}  ${TARGET} "mkdir -p .ssh && echo '${PUBKEY}' >> .ssh/authorized_keys" || exit 1;
fi

#ssh-copy-id ${TARGET}  > /dev/null



