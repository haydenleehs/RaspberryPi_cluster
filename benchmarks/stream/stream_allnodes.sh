#!/bin/bash
#SBATCH --job-name=stream-all
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --exclusive
#SBATCH --time=00:05:00
#SBATCH --output=/clusterfs/stream/%x-%j.out

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=true
srun --label bash -c 'echo "host=$(hostname)"; /clusterfs/stream/stream_c.exe | grep -E "Copy|Scale|Add|Triad"'
