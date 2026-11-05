#!/bin/bash
#SBATCH --job-name=osu-pairs
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:20:00
#SBATCH --output=/clusterfs/osu/%x-%j.out

OSU=/clusterfs/osu/libexec/osu-micro-benchmarks/mpi
export OMPI_MCA_btl_tcp_if_include=eth0

N=(picluster-node01 picluster-node02 picluster-node03 picluster-node04)
for i in 0 1 2 3; do for j in 0 1 2 3; do
  [ $i -lt $j ] || continue
  echo "===== ${N[$i]} <-> ${N[$j]} ====="
  mpirun -n 2 --host ${N[$i]},${N[$j]} $OSU/pt2pt/osu_bw -m 1048576:1048576
done; done

