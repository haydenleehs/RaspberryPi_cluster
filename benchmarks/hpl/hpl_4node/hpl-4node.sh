#!/bin/bash
#SBATCH --job-name=hpl-4node
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=4
#SBATCH --exclusive
#SBATCH --time=01:00:00
#SBATCH --output=/clusterfs/hpl/hpl_4node/%x-%j.out

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
cd /clusterfs/hpl/hpl_4node
echo "nodes=$SLURM_JOB_NODELIST ranks=$SLURM_NTASKS"
scontrol show hostnames $SLURM_JOB_NODELIST | awk '{print $1" slots=4"}' > hosts.txt
mpirun -n 16 --hostfile hosts.txt ./xhpl
