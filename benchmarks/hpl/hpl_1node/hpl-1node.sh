#!/bin/bash
#SBATCH --job-name=hpl-1node
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --exclusive
#SBATCH --time=01:00:00
#SBATCH --output=/clusterfs/hpl/hpl_1node/%x-%j.out

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
D=/clusterfs/hpl/hpl_1node
cd $D

# one logger per allocated node, writing to the run directory
srun --overlap --nodes=$SLURM_JOB_NUM_NODES --ntasks-per-node=1 --ntasks=$SLURM_JOB_NUM_NODES \
  bash -c 'exec /clusterfs/hpl/templog.sh '$D'/monitor_$(hostname)_'$SLURM_JOB_ID'.log' &
LOGGER=$!
trap 'kill $LOGGER 2>/dev/null' EXIT

echo "nodes=$SLURM_JOB_NODELIST ranks=$SLURM_NTASKS"
scontrol show hostnames $SLURM_JOB_NODELIST | awk '{print $1" slots=4"}' > hosts.txt
sleep 10
mpirun -n 4 --hostfile hosts.txt ./xhpl
sleep 10
