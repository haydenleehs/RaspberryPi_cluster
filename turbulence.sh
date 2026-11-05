#!/bin/bash
#SBATCH --partition=cluster
#SBATCH --time=00:05:00
#SBATCH --output=/clusterfs/aero_turb/mc-%x-%j.out

export OMP_NUM_THREADS=1
cd /clusterfs/aero_turb

ANGLE=${1:-6.0}
CAMBER=${2:-4.0}
THICK=${3:-12.0}
TURB=${4:-2.5}
SAMPLES=${5:-40000000}
LABEL=${6:-"run"}

mpirun -n "$SLURM_NTASKS" python3 /clusterfs/aero_turb/turbulence_mc.py \
    "$ANGLE" "$CAMBER" "$THICK" "$TURB" "$SAMPLES" "$LABEL"
