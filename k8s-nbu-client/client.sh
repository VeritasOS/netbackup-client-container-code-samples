#!/bin/sh

set -eu -o pipefail

CREATE=1
DELETE=2
LIST=3

op=0
master=
client=
yaml=
unique=
verbose=0

usage()
{
	echo "$0 create -M <master-server> -c <client-name> -u <unique-id> -f <yaml-file>"
	echo "$0 delete -u <unique-id>"
	echo "$0 list -u <unique-id> [-v]"
}

while test $# -gt 0;
do
	case $1 in
		create) op=${CREATE};;
		delete) op=${DELETE};;
		list) op=${LIST};;
		-M) master=$2; shift;;
		-c) client=$2; shift;;
		-f) yaml=$2; shift;;
		-u) unique=$2; shift;;
		-v) verbose=1;;
		*) usage; exit 1;;
	esac
	shift
done

if test ${op} -eq 0;
then
	echo "Either create, delete or list must be specified";
	usage
	exit 1
fi

if test ${op} -eq ${CREATE};
then
	if test "x${master}" = "x";
	then
		echo "Master server must be specified";
		usage
		exit 1
	fi

	if test "x${client}" = "x";
	then
		echo "Client name must be specified";
		usage
		exit 1
	fi

	if test "x${yaml}" = "x";
	then
		echo "Template file must be specified";
		usage
		exit 1
	fi
fi

if test "x${unique}" = "x";
then
	echo "Unique identifier must be specified";
	usage
	exit 1
fi

tmp_sed_file="sed.pattern.$$"
tmp_yaml_file="$$.yaml"
short_client=`echo ${client} | cut -f 1 -d '.'`
ipaddr=`dig +short ${client} 2> /dev/null`
if test "x${ipaddr}" = "x";
then
	ipaddr=`host ${client} | cut -f 4 -d ' '`
fi

rm_tmp_files()
{
	/bin/rm -f ${tmp_sed_file} ${tmp_yaml_file}
}

trap rm_tmp_files INT TERM QUIT

if test ${op} -eq ${CREATE};
then
	echo "s/__USER__/${USER}/g" > ${tmp_sed_file}
	echo "s/__UNIQUE__/${unique}/g" >> ${tmp_sed_file}
	echo "s/__MASTER__/${master}/g" >> ${tmp_sed_file}
	echo "s/__CLIENT__/${client}/g" >> ${tmp_sed_file}
	echo "s/__SHORT_CLIENT__/${short_client}/g" >> ${tmp_sed_file}
	echo "s/__IPADDR__/${ipaddr}/g" >> ${tmp_sed_file}

	cat ${yaml} | sed -f ${tmp_sed_file} > ${tmp_yaml_file}
	kubectl create -f ${tmp_yaml_file}
	if test $? -eq 0;
	then
		rm_tmp_files
	fi
elif test ${op} -eq ${DELETE};
then
	kubectl delete pods,pvc,services --selector uniq=${unique}
elif test ${op} -eq ${LIST};
then
	if test ${verbose} -eq 1;
	then
		kubectl describe pods,pvc,services --selector uniq=${unique}
	fi
	kubectl get pods,pvc,services --selector uniq=${unique} -o wide
fi
