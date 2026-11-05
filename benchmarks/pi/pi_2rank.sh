#!/bin/bash
#SBATCH --job-name=pi-2rank
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/pi/%x-%j.out

export OMP_NUM_THREADS=1
cd /clusterfs/pi
echo "host=$(hostname)  ranks=$SLURM_NTASKS"
mpirun -n "$SLURM_NTASKS" python3 /clusterfs/pi/pi_montecarlo.py
