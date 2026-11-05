#!/bin/bash
#SBATCH --job-name=osu-coll
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:20:00
#SBATCH --output=/clusterfs/osu/%x-%j.out

OSU=/clusterfs/osu/libexec/osu-micro-benchmarks/mpi
export OMPI_MCA_btl_tcp_if_include=eth0

echo "nodes=$SLURM_JOB_NODELIST  ranks=$SLURM_NTASKS"
for t in osu_barrier osu_allreduce osu_alltoall; do
  echo "===== $t ====="
  mpirun -n "$SLURM_NTASKS" --map-by node --bind-to core $OSU/collective/$t -m 1:1048576
done
