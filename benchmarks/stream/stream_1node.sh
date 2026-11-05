#!/bin/bash
#SBATCH --job-name=stream-1node
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --exclusive
#SBATCH --time=00:05:00
#SBATCH --output=/clusterfs/stream/%x-%j.out

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=true
echo "host=$(hostname) threads=$OMP_NUM_THREADS"
/clusterfs/stream/stream_c.exe
