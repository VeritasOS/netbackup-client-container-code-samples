This sample explains how to deploy NetBackup client container in Kubernets.

client.sh is use to manage NetBackup client container. 
	The NetBackup client container uses two volumes: 
		i) -nb-client-pvc [NetBackup specific volume]. 
		ii) -nb-dump-pvc [Dump volume mounted as /mnt/dump inside the container, which is used as a staging location for any application data].

	Example: client.sh create -M <master-server> -c <client-name> -u <unique-id> -f client.yaml 
	This starts the NetBackup client container. 
	Set up credentials as needed.
