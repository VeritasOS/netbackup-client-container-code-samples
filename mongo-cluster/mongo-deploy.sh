#!/bin/sh

set -eu -o pipefail

source helper.sh

router=
router_config=
name=
replicas=2
unique=
yaml=

usage()
{
	echo "$0 -n <sharded-replication-set-name> -u <unique-id> -f <yaml-file>"
	echo "    [-r <router-name>] [-c <replica-count>]"
}

tmp_sed_file="sed.pattern.$$"
tmp_yaml_file="$$.yaml"

rm_tmp_files()
{
	/bin/rm -f ${tmp_sed_file} ${tmp_yaml_file}
}

validate_args() {
	if [ "x${name}" = "x" ]
	then
		echo "Name must be specified";
		usage
		exit 1
	fi

	if [ "x${unique}" = "x" ]
	then
		echo "Unique identifier must be specified";
		usage
		exit 1
	fi

	if [ "x${yaml}" = "x" ]
	then
		echo "YAML file must be specified";
		usage
		exit 1
	fi
}

while [ $# -gt 0 ]
do
	case $1 in
		-c) replicas=$2; shift;;
		-f) yaml=$2; shift;;
		-n) name=$2; shift;;
		-r) router=$2; shift;;
		-u) unique=$2; shift;;
		*)  usage; exit 1;;
	esac
	shift
done

validate_args

if [ "x${router}" != "x" ]
then
	get_fqdn ${name}

	first_time=1
	router_config="${name}\/"
	for i in ${fqdn_array[@]} ;
	do
		if [ ${first_time} -eq 0 ]
		then
			router_config="${router_config},"
		fi
		router_config="${router_config}${i}:27017"
		first_time=0
	done

	name=${router}
fi

trap rm_tmp_files INT TERM QUIT

echo "s/__USER__/${USER}/g" > ${tmp_sed_file}
echo "s/__NAME__/${name}/g" >> ${tmp_sed_file}
echo "s/__UNIQUE_ID__/${unique}/g" >> ${tmp_sed_file}
echo "s/__ROUTER_CONFIG__/${router_config}/g" >> ${tmp_sed_file}
echo "s/__REPLICAS__/${replicas}/g" >> ${tmp_sed_file}

cat ${yaml} | sed -f ${tmp_sed_file} > ${tmp_yaml_file}
kubectl create -f ${tmp_yaml_file}
if [ $? -eq 0 ]
then
	rm_tmp_files
fi

sleep 10

if [ "x${router}" != "x" ]
then
	wait_for_pod_ready "${name}-pod"
else
	r=0
	while [ ${r} -lt ${replicas} ]
	do
		wait_for_pod_ready "${name}-ss-${r}"
		r=`expr $r + 1`
	done
fi

exit 0
