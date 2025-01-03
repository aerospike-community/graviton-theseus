#!/bin/bash

refresh_known_hosts() {
	for host in $@; do
		ssh-keygen -R "${host}"
		ssh-keyscan "${host}" >> ~/.ssh/known_hosts
	done
}

nearest_power_of_two() {
    local n=$1

    if (( n & (n - 1) == 0 )); then
        echo $n
        return
    fi

    # Calculate the next highest power of two
    local higher=$n
    higher=$((higher - 1))
    higher=$((higher | higher >> 1))
    higher=$((higher | higher >> 2))
    higher=$((higher | higher >> 4))
    higher=$((higher | higher >> 8))
    higher=$((higher + 1))

    local lower=$((higher >> 1))

    if (( n - lower < higher - n )); then
        echo $lower
    else
        echo $higher
    fi
}

reconfigure_drives() {
    local cluster_name=$1
    local nodes_arg="-l all"
    if [ "$2" != "" ]; then
      local nodes=$2
      local nodes_arg="-l $2"
      echo $nodes_arg
    fi


    echo "stopping cluster ${cluster_name}..."
    aerolab cluster attach -n "${cluster_name}" --parallel $nodes_arg systemctl stop aerospike

    sleep 10
    # index-type flash {
    #     evict-mounts-pct 90
    #     mount /mnt/nvme1n1p4
    #     mount /mnt/nvme2n1p4
    #     mounts-budget 300G
    # }
    # partition-tree-sprigs 16384

    MIN_NUMBER_OF_NODES=7
    REPLICATION_FACTOR=2

    TERABYTE=$(( 1024*1024*1024*1024 ))

    PARTITIONS=4096
    RECORDS_PER_SPRIG=32 # 64 entries with a fill factor of 50%
    BLOCK_SIZE=4096
    TOTAL_KEYS="${USER_PROFILE_ENTRIES}"

    PARTITION_TREE_SPRIGS=$((TOTAL_KEYS/RECORDS_PER_SPRIG/PARTITIONS))

    # Calculate nearest power of two
    PARTITION_TREE_SPRIGS=$(nearest_power_of_two $PARTITION_TREE_SPRIGS)

    PRIMARY_INDEX_SIZE=$(( (((PARTITIONS * REPLICATION_FACTOR) / MIN_NUMBER_OF_NODES) * PARTITION_TREE_SPRIGS) * BLOCK_SIZE ))

    echo "partitioning cluster nvme drives..."
    # If the cluster already existed, this will wipe out the previous run's data
    aerolab cluster partition create -n "${cluster_name}" --filter-type=nvme -p 2,22,22,22,22,10 $nodes_arg # TODO: Calculate this based on disk size

    aerolab cluster partition conf -n ${cluster_name} --namespace=campaign --filter-type=nvme --filter-partitions=1 --configure=device $nodes_arg

    aerolab cluster partition mkfs -n ${cluster_name} --filter-type=nvme --filter-partitions=6 $nodes_arg
    aerolab cluster partition conf -n ${cluster_name} --namespace=user-profile --filter-type=nvme --filter-partitions=2,3,4,5 --configure=device $nodes_arg
    aerolab cluster partition conf -n ${cluster_name} --namespace=user-profile --filter-type=nvme --filter-partitions=6 --configure=allflash $nodes_arg

    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.index-type flash.mounts-budget" "${PRIMARY_INDEX_SIZE}"
    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.index-type flash.evict-mounts-pct" 90
    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.partition-tree-sprigs" ${PARTITION_TREE_SPRIGS}

    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.storage-engine device.compression" zstd
    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.storage-engine device.compression-level" 4

    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace campaign.storage-engine device.compression" zstd
    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace campaign.storage-engine device.compression-level" 4

    aerolab cluster partition list $nodes_arg -n ${cluster_name}

    if [ "${PRIMARY_INDEX_SIZE}" -gt $(( 2 * TERABYTE )) ]; then
      aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.index-stage-size" 2G
    fi

    aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.storage-engine device.stop-writes-used-pct" 80

    # V7.0.x
    if [ -v WRITE_BLOCK_SIZE ]; then
      echo "setting write block size to ${WRITE_BLOCK_SIZE}"
      aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace campaign.storage-engine device.write-block-size" ${WRITE_BLOCK_SIZE}
      aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.storage-engine device.write-block-size" ${WRITE_BLOCK_SIZE}
    fi

    # V7.1.x
    if [ -v FLUSH_SIZE ]; then
      echo "setting flush size to ${FLUSH_SIZE}"
      aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace campaign.storage-engine device.flush-size" ${FLUSH_SIZE}
      aerolab conf adjust $nodes_arg -n ${cluster_name} set "namespace user-profile.storage-engine device.flush-size" ${FLUSH_SIZE}
    fi

    aerolab conf adjust $nodes_arg --name ${cluster_name} set "namespace campaign.enable-benchmarks-write" true
    aerolab conf adjust $nodes_arg --name ${cluster_name} set "namespace user-profile.enable-benchmarks-write" true

    aerolab conf adjust $nodes_arg --name ${cluster_name} set "namespace campaign.storage-engine device.enable-benchmarks-write" true
    aerolab conf adjust $nodes_arg --name ${cluster_name} set "namespace user-profile.storage-engine device.enable-benchmarks-write" true

    aerolab conf adjust $nodes_arg -n ${cluster_name} set "service.cluster-name" ${cluster_name}

    aerolab conf fix-mesh $nodes_arg -n "${cluster_name}"
}

