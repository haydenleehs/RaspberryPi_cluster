#!/bin/bash
#SBATCH --job-name=stream-sweep
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --exclusive
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/stream/%x-%j.out

export OMP_PROC_BIND=true
echo "host=$(hostname)"
for t in 1 2 4; do
  echo "=== threads=$t ==="
  OMP_NUM_THREADS=$t /clusterfs/stream/stream_c.exe | grep -E "Copy|Scale|Add|Triad"
done
