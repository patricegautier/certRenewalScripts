# Cert Renewal Made Easy


This tool automates the installation of Let's Encrypt SSL Certs to certain devices and uses Gandi's LiveDNS API.


Pre-requisites:

• All your target devices must have a FQDN
• A Gandi account and it's associated Live DNS Key
	See https://doc.livedns.gandi.net
	if you put this key in ~/.ssh/gandiLiveDNS.key it will get picked up automatically
	
• you need to have SSH access to all the target devices.  
• all those target devices must have outside network access
• You need to have generated a local RSA SSH public/private key pair on your own computer 
	See for ex. https://www.siteground.com/kb/generate_ssh_key_in_linux/


• The main script you need to run from your computer is updateRemoteCerts.sh
	 you can put a list of user@FQDNs in ~/.ssh/remoteCertHosts.txt (1 per line) and the script will go through those, or specify on the command line

2 other ancillary pieces:
	updateLocalCerts.sh: this gets uploaded to each of the target devices and run there to perform the actual generation and installation. 
		it will also attempt to restart the right services to the new cert is picked up right away. Protect and UDMPs currently require operator intervention though
	updatePublicKey.sh: sets up an SSH public key on the remote hosts so you don't have to type your password all the time


The script uses acme.sh (https://github.com/acmesh-official/acme.sh) to generate the certificates and installs the requisite pieces in various spots.


Supported devices and services:

• Unifi Cloud Keys
	- Cloud Key controller
	- protect if installed.  Currently the only way I found to get protect to recognize the new certificate is to reboot the box
	
• UDMPs
	- this one requires manual operator intervention given the script must run inside the container.  If anyone knows how to do this from SSH, please ping me
• pihole
	- pihole running lighthttpd
• UNMS
	- currently assumes it's installed on a raspberry pi at /home/pi/unms
• Homebridge
	- not implemented yet
