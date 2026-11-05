#!/bin/bash
#SBATCH --partition=cluster
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/simulation/aero/%x-%j.out
export OMP_NUM_THREADS=1
cd /clusterfs/simulation/aero
mpirun -n "$SLURM_NTASKS" python3 aero_sweep.py 1
