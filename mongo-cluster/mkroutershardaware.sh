#!/bin/sh

set -eu -o pipefail

source helper.sh

usage()
{
	echo "$0 <router-name> <sharded-replication-set-name>"
}

router=$1
name=$2

if [ "x${name}" = "x" ]
then
	echo "Name must be specified";
	usage
	exit 1
fi

if [ "x${router}" = "x" ]
then
	echo "Router must be specified";
	usage
	exit 1
fi

get_fqdn ${name}
add_shard ${router} ${name}
