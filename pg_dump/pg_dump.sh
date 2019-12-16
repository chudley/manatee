#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

# Postgres backup script. This script takes a snapshot of the current postgres
# data dir, then mounts said snapshot, and dumps all of the tables from
# postgres, and uploads them to manta

source /opt/smartdc/manatee/pg_dump/pg_backup_common.sh

PG_START_TIMEOUT=$1
DATASET=
DUMP_DATASET=
PG_DIR=
UPLOAD_SNAPSHOT=
MY_IP=
SHARD_NAME=
ZK_IP=

# mainline

if [[ -z "$1" ]]
    then
        PG_START_TIMEOUT=10
    else
        PG_START_TIMEOUT=$1
fi

DATASET=$(cat $ZFS_CFG | json dataset)
[[ -n "$DATASET" ]] || fatal "unable to retrieve DATASET"
DUMP_DATASET=zones/$(zonename)/data/pg_dump
PG_DIR=/$DUMP_DATASET/data
UPLOAD_SNAPSHOT=$(cat $CFG | json -a upload_snapshot)
MY_IP=$(mdata-get sdc:nics.0.ip)
[[ -n "$MY_IP" ]] || fatal "Unable to retrieve our own IP address"
SHARD_NAME=$(cat $CFG | json -a service_name)
[[ -n "$SHARD_NAME" ]] || fatal 'Unable to retrieve $SHARD_NAME'
ZK_IP=$(cat $CFG | json -a zkCfg.servers.0.host)
[[ -n "$ZK_IP" ]] || fatal "Unable to retrieve nameservers from metadata"

get_self_role
if [[ $? = '1' ]]; then
    take_zfs_snapshot
    check_lock
    mount_data_set
    backup "DB"
    while ! upload_pg_dumps; do
        echo "uploading database dumps failed (will retry)"
        sleep 15
    done
    echo "successfully uploaded database dumps"
    cleanup
    exit 0
else
    echo "not performing backup, not lowest peer in shard"
    exit 0
fi
