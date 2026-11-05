#!/bin/bash
#SBATCH --job-name=pi-16rank
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/pi/%x-%j.out

export OMP_NUM_THREADS=1
cd /clusterfs/pi
echo "nodes=$SLURM_JOB_NODELIST  ranks=$SLURM_NTASKS"
mpirun -n "$SLURM_NTASKS" python3 /clusterfs/pi/pi_montecarlo.py

