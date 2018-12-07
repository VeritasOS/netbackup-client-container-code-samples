#!/bin/sh

set -eu -o pipefail

source helper.sh

CREATE=1
DELETE=2
LIST=3
BACKUP=4
RESTORE=5

op=0
replicas=2
router=
unique=
cfg_name=
unique_restore_id=
verbose=0
declare -a data_shards

usage()
{
	echo "$0 create -u <unique-id> -r <router-name> [-c <replica-count>]"
	echo "    -csrs <config-server-replica-set-name>"
	echo "    -srs <sharded-replica-set-name-1,sharded-replica-set-name-2,...>"
	echo "$0 delete -u <unique-id>"
	echo "    -csrs <config-server-replica-set-name>"
	echo "    -srs <sharded-replica-set-name-1,sharded-replica-set-name-2,...>"
	echo "$0 list -u <unique-id> [-v]"
	echo "    -csrs <config-server-replica-set-name>"
	echo "    -srs <sharded-replica-set-name-1,sharded-replica-set-name-2,...>"
	echo "$0 backup -u <unique-id> -r <router-name>"
	echo "    -csrs <config-server-replica-set-name>"
	echo "    -srs <sharded-replica-set-name-1,sharded-replica-set-name-2,...>"
	echo "$0 restore -ru <unique-restore-id> -u <unique-id> -r <router-name>"
	echo "    -csrs <config-server-replica-set-name>"
	echo "    -srs <sharded-replica-set-name-1,sharded-replica-set-name-2,...>"
}

validate_args() {
	if [ ${op} -eq 0 ]
	then
		echo "Either create, delete, or list must be specified";
		usage
		exit 1
	fi

	if [ ${op} -ne ${BACKUP} ]
	then
		if [ "x${unique}" = "x" ]
		then
			echo "Unique identifier must be specified";
			usage
			exit 1
		fi
	fi

	if [ ${op} -eq ${RESTORE} ]
	then
		if [ "x${unique_restore_id}" = "x" ]
		then
			echo "Unique identifier for restore must be specified";
			usage
			exit 1
		fi
	fi

	if [ "x{router}" = "x" ]
	then
		echo "mongo router name must be specified";
		usage
		exit 1
	fi

	if [ "x{cfg_name}" = "x" ]
	then
		echo "mongo config server replica set name must be specified";
		usage
		exit 1
	fi

	if [ ${#data_shards[@]} -eq 0 ]
	then
		echo "mongo data shard replica set name(s) must be specified";
		usage
		exit 1
	fi
}

while [ $# -gt 0 ]
do
	case $1 in
		create)     op=${CREATE};;
		delete)     op=${DELETE};;
		list)       op=${LIST};;
		backup)     op=${BACKUP};;
		restore)    op=${RESTORE};;
		-c)         replicas=$2; shift;;
		-csrs)      cfg_name=$2; shift;;
		-r)         router=$2; shift;;
		-ru)        unique_restore_id=$2; shift;;
		-srs)       data_shards=(`echo $2 | sed 's/,/\n/g'`); shift;;
		-u)         unique=$2; shift;;
		-v)         verbose=1;;
		*)          usage; exit 1;;
	esac
	shift
done

validate_args

if [ ${op} -eq ${CREATE} ]
then
	# Start Mongo Sharded Replication Set (SRS)
	for i in ${data_shards[@]}
	do
		mongo-deploy.sh -n ${i} -u ${unique} -c ${replicas} -f srs.yaml
		initrep.sh ${i}
	done

	# Start Mongo Config Server Replication Set (CSRS)
	mongo-deploy.sh -n ${cfg_name} -u ${unique} -c ${replicas} -f csrs.yaml
	initrep.sh ${cfg_name}

	# Start Mongo Router
	mongo-deploy.sh -r ${router} -n ${cfg_name} -u ${unique} -f router.yaml

	# Make router aware of shards
	for i in ${data_shards[@]} ;
	do
		mkroutershardaware.sh ${router} ${i}
	done

	# Insert data into the database
	kubectl cp insert.js ${router}-pod:/tmp/insert.js
	kubectl exec ${router}-pod -- mongo --quiet /tmp/insert.js

elif [ ${op} -eq ${DELETE} ]
then
	kubectl delete services --selector uniq=${unique}
	kubectl delete pod/${router}-pod
	kubectl delete statefulsets --selector uniq=${unique}
    podcnt=100
	while [ ${podcnt} -ne 0 ]
	do
		podcnt=`kubectl get pod --selector uniq=${unique} 2>/dev/null | wc -l`
	done
	kubectl delete pvc --selector role=${cfg_name}
	for i in ${data_shards[@]}
	do
		kubectl delete pvc --selector role=${i}
	done
	kubectl delete all --selector uniq=${unique}
elif [ ${op} -eq ${LIST} ]
then
        if test ${verbose} -eq 1;
        then
		kubectl describe all --selector uniq=${unique}
		kubectl describe pvc --selector role=${cfg_name}
		for i in ${data_shards[@]}
		do
			kubectl describe pvc --selector role=${i}
		done
        fi

	kubectl get all --selector uniq=${unique} -o wide
	kubectl get pvc --selector role=${cfg_name} -o wide
	for i in ${data_shards[@]}
	do
		kubectl get pvc --selector role=${i} -o wide
	done
elif [ ${op} -eq ${BACKUP} ]
then
	stop_balancer ${router}

	quiesce_rs ${cfg_name}

	for i in ${data_shards[@]} ;
	do
		quiesce_rs ${i}
	done

	datestr=`date +%F_%T`
	mongodump ${cfg_name} ${quiesced_pods[0]} ${datestr}

	didx=1
	for i in ${data_shards[@]} ;
	do
		mongodump ${i} ${quiesced_pods[${didx}]} ${datestr}
		didx=`expr $didx + 1`
	done

	for i in ${quiesced_pods[@]}
	do
		unquiesce_rs $i
	done

	sleep 10

	start_balancer ${router}

	echo "Mongo data is dumped to:"
	for i in ${dump_paths[@]}
	do
		echo ${i}
	done
	echo "Unique key for restore is ${datestr}"
elif [ ${op} -eq ${RESTORE} ]
then
	# Start Mongo Sharded Replication Set (SRS)
	for i in ${data_shards[@]}
	do
		mongo-deploy.sh -n ${i} -u ${unique} -c ${replicas} -f srs.yaml
		initrep.sh ${i}
	done

	# Start Mongo Config Server Replication Set (CSRS)
	mongo-deploy.sh -n ${cfg_name} -u ${unique} -c ${replicas} -f csrs.yaml
	initrep.sh ${cfg_name}

	# Start Mongo Router
	mongo-deploy.sh -r ${router} -n ${cfg_name} -u ${unique} -f router.yaml

	# Make router aware of shards
	for i in ${data_shards[@]} ;
	do
		mkroutershardaware.sh ${router} ${i}
	done

	sleep 10

	# Restore data shards
	kubectl delete pod/${router}-pod service/${router}-svc
	for i in ${data_shards[@]}
	do
		primary=`find_primary ${i}`
		echo ${primary}
		mongorestore ${i} ${primary} ${unique_restore_id}
	done

	# Restore config shards
	primary=`find_primary ${cfg_name}`
	mongorestore ${cfg_name} ${primary} ${unique_restore_id}

	# Restart Mongo Router
	mongo-deploy.sh -r ${router} -n ${cfg_name} -u ${unique} -f router.yaml
fi
