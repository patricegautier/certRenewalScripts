#!/bin/bash
# set -x

usage()
{
	echo "Usage "${0}" user@targetMachine"
    echo "  returns "
	exit 2
}


TARGET=$@


if [ -z ${TARGET} ]; then
	usage
fi

ssh -q -o "BatchMode yes" ${TARGET} true
PUBKEY_OK=$?

if [ ${PUBKEY_OK} != '0'  ]; then
	echo "Need to update public key for " ${TARGET}
   	KEY_PATH=${HOME}"/.ssh/id_rsa.pub"
   	PUBKEY=$(<${KEY_PATH}) || exit 1;
   	ssh  ${TARGET} "mkdir -p .ssh && echo '${PUBKEY}' >> .ssh/authorized_keys" || exit 1;
fi



