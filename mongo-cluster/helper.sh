
declare -a fqdn_array
declare -a quiesced_pods
declare -a dump_paths

wait_for_pod_ready() {
	# wait for 5 minutes
	cnt=0
	while [ $cnt -lt 60 ]
	do
		ready=`kubectl get pod/$1 -o jsonpath="{.status.containerStatuses[0].ready}{'\n'}"`
		if [ "x${ready}" != "xtrue" ]
		then
			sleep 5
		else
			break
		fi
		cnt=`expr $cnt + 1`
	done
}

get_fqdn() {
	echo "Get fqdn for pods matching role $1"

	replica_set=(`kubectl get --no-headers=true pods --selector role=$1 -o custom-columns=:metadata.name`)

	num=0
	for i in ${replica_set[@]} ;
	do
		fqdn_array[num++]=`kubectl exec $i -- hostname -f`
	done

	echo "fqdn found are: ${fqdn_array[@]}"
}

# args: shard_name
rs_initiate() {
	kubectl exec $1-ss-0 -- bash -c "echo 'rs.initiate( { _id:\"$1\", members: [ { _id:0, host:\"${fqdn_array[0]}:27017\" }, { _id:1, host:\"${fqdn_array[1]}:27017\" } ] } )' | mongo --quiet"
	sleep 5
	kubectl exec $1-ss-0 -- mongo --quiet --eval 'rs.status()'
}

# args: pod_name shard_name
add_shard() {
	kubectl exec $1-pod -- bash -c "echo 'sh.addShard( \"$2/${fqdn_array[0]}:27017\" )' | mongo --quiet"
	sleep 5
	kubectl exec $1-pod -- mongo --quiet --eval 'sh.status()'
}

# args: router_name
stop_balancer() {
	router_pod=`kubectl get --no-headers=true pods --selector role=$1 -o custom-columns=:metadata.name`
	kubectl exec ${router_pod} -- mongo config --quiet --eval 'sh.stopBalancer()'
	if [ $? -ne 0 ]
	then
		echo "Failed to stop balancer on ${router_pod}"
		exit 1
	else
		echo "Stopped balancer successfully on ${router_pod}"
	fi
}

# args: router_name
start_balancer() {
	router_pod=`kubectl get --no-headers=true pods --selector role=$1 -o custom-columns=:metadata.name`
	kubectl exec ${router_pod} -- mongo config --quiet --eval 'sh.setBalancerState(true)'
	if [ $? -ne 0 ]
	then
		echo "Failed to start balancer on ${router_pod}"
		exit 1
	else
		echo "Started balancer successfully on ${router_pod}"
	fi
}

# args: shard_name
# returns: pod_name (one that is quiesced)
quiesce_rs() {
	replica_set=(`kubectl get --no-headers=true pods --selector role=$1 -o custom-columns=:metadata.name`)
	for i in ${replica_set[@]} ;
	do
		secondary=`kubectl exec $i -- mongo --quiet --eval 'db.isMaster().secondary'`
		if [ ${secondary} = "true" ]
		then
			kubectl exec ${i} -- mongo --quiet --eval 'db.fsyncLock( { force : true } )'
			quiesced_pods+=(${i})
			break
		fi
	done
}

# args: pod_name
unquiesce_rs() {
	kubectl exec $1 -- mongo --quiet --eval 'db.fsyncUnlock()'
}

# args: shard_name pod_name date_string (date +%F_%T)
mongodump() {
	path="/mnt/dump/mongo/$1/dump-$3"
	kubectl exec $2 -- mongodump --oplog --out ${path}
	dump_paths+=(${path})
}

# args: cfg_name
find_primary() {
	replica_set=(`kubectl get --no-headers=true pods --selector role=$1 -o custom-columns=:metadata.name`)
	for i in ${replica_set[@]} ;
	do
		primary=`kubectl exec $i -- mongo --quiet --eval 'db.isMaster().ismaster'`
		if [ ${primary} = "true" ]
		then
			echo $i
			break
		fi
	done
}

# args: shard_name pod_name date_string (date +%F_%T)
mongorestore() {
	path="/mnt/dump/mongo/$1/dump-$3"
	kubectl exec $2 -- mongorestore --oplogReplay ${path}
}
