#!/bin/bash
# Run NCCL test on a cluster - from Jingchao
set -eux

# Disable host key checking
cat > "$HOME/.ssh/config" <<EOL
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOL
chmod 600 "$HOME/.ssh/config"

# Ensure the hostfile parameter is provided
if [ -z "${1:-}" ]; then
  echo "Error: Missing hostfile parameter."
  echo "Usage: $0 <hostfile>"
  exit 1
fi

# Run NCCL test
module load mpi/hpcx

export HOSTFILE=$1
export SCALE=$(wc -l < "$HOSTFILE")
export DEVICES=8

sharp_args="-x NCCL_COLLNET_ENABLE=1 \
-x NCCL_ALGO=CollnetChain,NVLS \
-x SHARP_COLL_ENABLE_SAT=1 \
-x SHARP_COLL_LOG_LEVEL=3 \
-x SHARP_COLL_ENABLE_PCI_RELAXED_ORDERING=1 \
-x SHARP_SMX_UCX_INTERFACE=mlx5_ib0:1"

mpirun -np $(( SCALE * DEVICES )) \
    --map-by ppr:8:node \
    -hostfile $HOSTFILE \
    -mca plm_rsh_no_tree_spawn 1 \
    -mca plm_rsh_num_concurrent 800 \
    -mca coll_hcoll_enable 0 \
    -x LD_LIBRARY_PATH \
    -x CUDA_DEVICE_ORDER=PCI_BUS_ID \
    -x UCX_TLS=rc \
    -x UCX_NET_DEVICES=mlx5_ib0:1 \
    -x NCCL_SOCKET_IFNAME=eth0 \
    -x NCCL_DEBUG=WARN \
    -x NCCL_MIN_NCHANNELS=32 \
    -x NCCL_IB_QPS_PER_CONNECTION=4 \
    -x NCCL_P2P_NET_CHUNKSIZE=$((512*1024)) \
    -x NCCL_PXN_DISABLE=1 \
    -x NCCL_TOPO_FILE=/opt/microsoft/ndv5-topo.xml \
    -x NCCL_IGNORE_CPU_AFFINITY=1 \
    /opt/nccl-tests/build/all_reduce_perf -g 1 -t 1 -b 8G -e 8G -f 0 -N 10 -R 1
