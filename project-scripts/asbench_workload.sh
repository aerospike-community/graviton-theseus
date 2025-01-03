#!/bin/bash

set -e

# Default values
CLUSTER_NAME="gcptest"
NAMESPACE="test"
CLIENT_COUNT=1
THREAD_COUNT=16
WORKLOAD_TYPE=hydrate
TOTAL_KEYS=500000001
START_KEY=0
TOTAL_TPS=500000
BIN_SIZE=1000
COMPRESSION_RATIO=1
READ_PERCENTAGE=50
TIMEOUT=86400

# Make sure this isn't being set by the environment
unset CLIENT_CLUSTER_NAME

# Gaussian Workload
STD_DEVIATION=3

show_help() {
cat << EOF
Usage: ${0##*/} [options]

This script configures a cluster and runs a workload

    --help                        display this help and exit
    --cluster-name NAME           set the cluster name (default: $CLUSTER_NAME)
    --namespace NAME              set the cluster name (default: $NAMESPACE)
    --client-cluster-name NAME    Set the client cluster name
    --client-count NUM            set the number of concurrent workload sessions on each client machine (default: $CLIENT_COUNT)
    --thread-count NUM            set the number of concurrent workload threads (default: $THREAD_COUNT)
    --workload-type TYPE          set the workload type to hydrate, workload, gaussian, or focus (default: $WORKLOAD_TYPE})
    --total-tps NUM               the number of transactions per second to deliver to the server (default: $TOTAL_TPS)
    --total-keys NUM              the number of keys to use for this test (default: $TOTAL_KEYS)
    --start-key NUM               the start key to use for this test (default: $START_KEY)
    --bin-size NUM                the size of the bin to insert (default: $BIN_SIZE)
    --compression-ratio NUM       the compression ratio to simulate (default: $COMPRESSION_RATIO)
    --read-percentage NUM         the percentage of the workload to be reads (default: ${READ_PERCENTAGE})
    --timeout NUM                 number of seconds to run asbench (default: $TIMEOUT)
    --async                       use asynchronous I/O
    --tls                         use TLS for client connections

    Gaussian Workload
    --standard-deviation          standard deviation to use for workload (default: $STD_DEVIATION)

    Workload
    --hot-key                     simulate a hot key
EOF
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help) show_help; exit 0 ;;
        --cluster-name) CLUSTER_NAME="$2"; shift ;;
        --namespace) NAMESPACE="$2"; shift ;;
        --client-cluster-name) CLIENT_CLUSTER_NAME="$2"; shift ;;
        --client-count) CLIENT_COUNT="$2"; shift ;;
        --thread-count) THREAD_COUNT="$2"; shift ;;
        --workload-type) WORKLOAD_TYPE="$2"; shift ;;
        --total-tps) TOTAL_TPS="$2"; shift ;;
        --total-keys) TOTAL_KEYS="$2"; shift ;;
        --start-key) START_KEY="$2"; shift ;;
        --bin-size) BIN_SIZE="$2"; shift; ;;
        --compression-ratio) COMPRESSION_RATIO="$2"; shift; ;;
        --read-percentage) READ_PERCENTAGE="$2"; shift; ;;
        --timeout) TIMEOUT="$2"; shift; ;;
        --async) ASYNCHRONOUS_IO=true; ;;
        --tls) USE_TLS=true; ;;
        --hot-key) HOT_KEY=true; ;;

        # Gaussian Workload
        --standard-deviation) STD_DEVIATION="$2"; shift ;;

        # Postprocessing
        --postprocess) POSTPROCESS=true; RESULTS_DIR="$2"; shift ;;

        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

AEROLAB_INVENTORY_FILE=$(mktemp)
aerolab inventory list -j  > "${AEROLAB_INVENTORY_FILE}"

if ! [ -v CLIENT_CLUSTER_NAME ]; then
    CLIENT_CLUSTER_COUNT=$(echo "select count(*) from aerolab_cluster where project = '${PROJECT_NAME}' and cluster_type = 'tools';" \
                        | steampipe "${AEROLAB_INVENTORY_FILE}" 2>/dev/null)

    if [ "${CLIENT_CLUSTER_COUNT}" -ne 1 ]; then
      echo "expected one tools cluster got: ${CLIENT_CLUSTER_COUNT}"
      exit 1
    fi

    CLIENT_CLUSTER_NAME=$(echo "select cluster_name from aerolab_cluster where project = '${PROJECT_NAME}' and cluster_type = 'tools';" \
                        | steampipe "${AEROLAB_INVENTORY_FILE}" 2>/dev/null)
fi

CLIENT_SERVER_COUNT=$(echo "select node_count from aerolab_cluster where project = '${PROJECT_NAME}' and cluster_type = 'tools' and cluster_name = '${CLIENT_CLUSTER_NAME}';" \
                        | steampipe "${AEROLAB_INVENTORY_FILE}" 2>/dev/null)

if [ "${CLIENT_SERVER_COUNT}" -le 1 ]; then
  echo "expected one tools node got: ${CLIENT_SERVER_COUNT}"
  exit 1
fi

#########################################
#             POSTPROCESSING
#########################################
if [ -v POSTPROCESS ]; then
    echo "postprocessing asbench results..."
    postprocess_dir="${RESULTS_DIR}/asbench-results"

    mkdir -p "$postprocess_dir"

    pdsh -g "${CLIENT_CLUSTER_NAME}" "cd /var/log/; make_percentile_plot -x 1000 -y 95 -t read ./asbench_*/read*.txt  -o client-read-percentiles-sla1ms.png"
    pdsh -g "${CLIENT_CLUSTER_NAME}" "cd /var/log/;  make_percentile_plot -x 2000 -y 95 -t write ./asbench_*/write*.txt -o client-write-percentiles-sla1ms.png"

    pdsh -g "${CLIENT_CLUSTER_NAME}" 'tar -cvzf /tmp/asbench_results.tar.gz /var/log/asbench* /var/log/client-read-percentiles-sla1ms.png /var/log/client-write-percentiles-sla1ms.png'
    rpdcp -g "${CLIENT_CLUSTER_NAME}" /tmp/asbench_results.tar.gz "${postprocess_dir}"

    exit 0
fi

INSTALLED_VERSION=$(aerolab attach shell -n "${CLUSTER_NAME}" -- bash -c 'rpm -q aerospike-server-enterprise --qf "%{VERSION}-%{RELEASE}"')

WORKLOAD_BINARY=asbench

cat << EOF
CLUSTER_NAME = ${CLUSTER_NAME}
CLIENT_CLUSTER_NAME = ${CLIENT_CLUSTER_NAME}
NAMESPACE = ${NAMESPACE}
INSTALLED_VERSION = ${INSTALLED_VERSION}
CLIENT_SERVER_COUNT= ${CLIENT_SERVER_COUNT}
CLIENT_COUNT = ${CLIENT_COUNT}
THREAD_COUNT = ${THREAD_COUNT}
WORKLOAD_TYPE = ${WORKLOAD_TYPE}
TOTAL_TPS = ${TOTAL_TPS}
TIMEOUT = ${TIMEOUT}
DATE = $(date -u)
WORKLOAD_BINARY = ${WORKLOAD_BINARY}

EOF

echo
echo "select * from aerolab_cluster where project = '${PROJECT_NAME}';" | steampipe ${AEROLAB_INVENTORY_FILE} -markdown 2>/dev/null
echo

aerolab attach shell -n "${CLUSTER_NAME}" -- cat /etc/aerospike/aerospike.conf

CLUSTER_HOST=$(echo "select node_name from aerolab_instance where project = '${PROJECT_NAME}' and cluster_name = '${CLUSTER_NAME}' LIMIT 1" \
                   | steampipe ${AEROLAB_INVENTORY_FILE} 2>/dev/null)

TOTAL_ASBENCH=$((CLIENT_SERVER_COUNT*CLIENT_COUNT))

TPS_PER_NODE=$((TOTAL_TPS/CLIENT_SERVER_COUNT))
TPS_PER_CLIENT=$((TPS_PER_NODE/CLIENT_COUNT))

DATA_SLICE=0

cleanup() {
  trap - INT TERM

  echo
  echo "killing asbench..."
  pdsh -g "${CLIENT_CLUSTER_NAME}" pkill asbench

  exit 0
}

trap cleanup INT TERM

# Calculate key ranges based on Gaussian distribution using Perl
calculate_key_range() {
    local start_key=$1
    local end_key=$2
    local std_dev=$3
    local num_clients=$4
    local total_tps=$5
    local data_slice=$6

    perl -MPOSIX -le '
    use List::Util qw(sum);

    # Read the arguments
    $start_key = '"$start_key"';
    $end_key = '"$end_key"';
    $std_dev = '"$std_dev"';
    $num_clients = '"$num_clients"';
    $total_tps = '"$total_tps"';
    $data_slice = '"$data_slice"';

    # Generate the ranges and calculate the TPS for each range
    my $range_per_client = int(($end_key - $start_key + 1) / $num_clients);
    my @tps_distribution = calculate_tps_distribution($num_clients, $std_dev, $total_tps);

    my $range_start = $start_key + $data_slice * $range_per_client;
    my $range_end = $data_slice == $num_clients - 1 ? $end_key : $range_start + $range_per_client - 1;
    my $tps = $total_tps == 0 ? 0 : $tps_distribution[$data_slice];
    print "$range_start $range_end $tps";

    sub calculate_tps_distribution {
        my ($num_clients, $std_dev, $total_tps) = @_;
        my @distribution;

        # Calculate a simple Gaussian distribution
        for (my $i = 0; $i < $num_clients; $i++) {
            my $x = $i - $num_clients / 2;
            my $tps = exp(-0.5 * ($x**2) / ($std_dev**2));
            push @distribution, $tps;
        }

        # Normalize to sum to 1 (proportionally scale)
        my $sum = sum @distribution;
        @distribution = map { $_ / $sum } @distribution;

        # Scale to total TPS
        @distribution = map { int($_ * $total_tps) } @distribution;

        return @distribution;
    }

    '
}

if [ -v USE_TLS ]; then
  TLSOPTIONS="--port 4333 --tls-enable --tls-cafile /etc/aerospike/ssl/tls1/cacert.pem --tls-keyfile /etc/aerospike/ssl/tls1/key.pem --tls-name tls1"
fi

if [ -v ASYNCHRONOUS_IO ]; then
  ASYNC_FLAGS="--async --conn-pools-per-node 1"
fi

if [ -v USE_TIMEOUT ]; then
  TIMEOUT_FLAGS="--read-timeout 30 --write-timeout 30 --max-retries=1 --sleep-between-retries 0 --read-socket-timeout 5000 --write-socket-timeout 5000"
fi

echo "starting ${WORKLOAD_BINARY} workload at $(date -u)..."

for CLIENT_NUM in $(seq 1 "${CLIENT_COUNT}")
do
  #########################################
  #                Hydrate
  #########################################
  if [ "${WORKLOAD_TYPE}" == "hydrate" ]; then
    KEYS=$((TOTAL_KEYS/CLIENT_SERVER_COUNT/CLIENT_COUNT))
    for NODE in $(seq 1 "${CLIENT_SERVER_COUNT}"); do
      CMD="run_asbench -h ${CLUSTER_HOST} -n ${NAMESPACE} -s testset -k ${KEYS} -K $(( (DATA_SLICE*KEYS) + START_KEY )) -o B${BIN_SIZE} -w I -z ${THREAD_COUNT} -g ${TPS_PER_CLIENT} --compression-ratio ${COMPRESSION_RATIO} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
      echo "+ ${CMD}"

      aerolab client attach -n "${CLIENT_CLUSTER_NAME}" -l "${NODE}" --detach -- /bin/bash -c "${CMD}"

      DATA_SLICE=$((DATA_SLICE+1))
    done

  #########################################
  #                Workload
  #########################################
  elif [ "${WORKLOAD_TYPE}" == "workload" ]; then
    CMD="run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -k ${TOTAL_KEYS} -K ${START_KEY} -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g ${TPS_PER_CLIENT} --compression-ratio ${COMPRESSION_RATIO} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
    echo "+ ${CMD}"

    aerolab client attach -n "${CLIENT_CLUSTER_NAME}" -l all --detach -- /bin/bash -c "${CMD}"

    if [ -v HOT_KEY ]; then
      if [ "${DATA_SLICE}" -eq 0 ]; then
        CMD="run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -K ${START_KEY} -k 1 -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g $((TPS_PER_CLIENT/CLIENT_SERVER_COUNT)) --compression-ratio ${COMPRESSION_RATIO} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
        echo "+ ${CMD}"

        aerolab client attach -n "${CLIENT_CLUSTER_NAME}" -l all --detach -- /bin/bash -c "${CMD}"
      fi
    fi

    DATA_SLICE=$((DATA_SLICE+1))

  #########################################
  #                Focus
  #########################################
  elif [ "${WORKLOAD_TYPE}" == "focus" ]; then
    for NODE in $(seq 1 "${CLIENT_SERVER_COUNT}"); do
      if [ $DATA_SLICE -eq 0 ]; then
        CMD="run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -K ${START_KEY} -k ${TOTAL_KEYS} -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g ${TPS_PER_CLIENT} --compression-ratio ${COMPRESSION_RATIO} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
      else
        CMD="run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -K ${START_KEY} -k $((TOTAL_KEYS/200)) -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g ${TPS_PER_CLIENT} --compression-ratio ${COMPRESSION_RATIO} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
      fi
      echo "+ ${CMD}"

      aerolab client attach -n "${CLIENT_CLUSTER_NAME}" -l "${NODE}" --detach -- /bin/bash -c "${CMD}"

      DATA_SLICE=$((DATA_SLICE+1))
    done

  #########################################
  #               Gaussian
  #########################################
  elif [ "${WORKLOAD_TYPE}" == "gaussian" ]; then

    for NODE in $(seq 1 "${CLIENT_SERVER_COUNT}"); do
    read -r start_key end_key tps <<< $(calculate_key_range ${START_KEY} $(( TOTAL_KEYS + START_KEY )) $STD_DEVIATION $TOTAL_ASBENCH $TOTAL_TPS $DATA_SLICE)

      if [ "${tps}" -gt 0 ] || [ "${TOTAL_TPS}" -eq 0 ]; then
        CMD="run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -K ${start_key} -k $((end_key-start_key)) -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g ${tps} --compression-ratio ${COMPRESSION_RATIO} ${TLSOPTIONS} ${ASYNC_FLAGS} -d"
        echo "+ ${CMD}"

        aerolab client attach -n "${CLIENT_CLUSTER_NAME}" -l "${NODE}" --detach -- /bin/bash -c "${CMD}"
      fi

      DATA_SLICE=$((DATA_SLICE+1))
    done

  else
    echo "invalid workload type ${WORKLOAD_TYPE}"
    exit 1
  fi

done

sleep 5

echo "started ${CLIENT_COUNT} ${WORKLOAD_BINARY} instances on ${CLIENT_SERVER_COUNT} nodes";

echo -n "waiting for ${WORKLOAD_BINARY} to complete..."

while pdsh -g "${CLIENT_CLUSTER_NAME}" -N "ps -ef | grep -v grep" | grep -q "${WORKLOAD_BINARY}"; do
  echo -n "."
  sleep 10
done

echo
echo "finished ${WORKLOAD_BINARY} workload at $(date -u)"


