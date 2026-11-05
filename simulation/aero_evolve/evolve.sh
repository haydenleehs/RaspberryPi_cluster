#!/bin/bash
#SBATCH --partition=cluster
#SBATCH --time=00:15:00
#SBATCH --output=/clusterfs/aero_evolve/%x-%j.out
export OMP_NUM_THREADS=1
cd /clusterfs/aero_evolve
mpirun -n "$SLURM_NTASKS" python3 aero_evolve.py "${PACE:-0}" 2400 30
