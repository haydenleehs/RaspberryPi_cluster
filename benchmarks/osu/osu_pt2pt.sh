#!/bin/bash
#SBATCH --job-name=osu-pt2pt
#SBATCH --partition=cluster
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:15:00
#SBATCH --output=/clusterfs/osu/%x-%j.out

OSU=/clusterfs/osu/libexec/osu-micro-benchmarks/mpi
export OMPI_MCA_btl_tcp_if_include=eth0     # force the cluster LAN

echo "nodes=$SLURM_JOB_NODELIST  ranks=$SLURM_NTASKS"
for t in osu_latency osu_bw osu_bibw; do
  echo "===== $t ====="
  mpirun -n 2 --map-by node --bind-to core $OSU/pt2pt/$t
done
