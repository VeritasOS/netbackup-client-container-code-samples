#!/bin/sh

# $Copyright: Copyright (c) 2018 Veritas Technologies LLC. All rights reserved $

set -eu -o pipefail

source helper.sh

usage()
{
	echo "$0 <sharded-replication-set-name>"
}

name=$1

if [ "x${name}" = "x" ]
then
	echo "Name must be specified";
	usage
	exit 1
fi

get_fqdn ${name}
rs_initiate ${name}
