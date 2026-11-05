# Raspberry Pi HPC Demo Cluster Build Guide - Part 3 (NFS + Script)


A single directory, `/clusterfs`, is exported from the login node and mounted
on every compute node. 

```bash
NODES="picluster-node01 picluster-node02 picluster-node03 picluster-node04"
```

If the node is not idle, resume it:

```bash
sinfo -R                                                   # shows the reason
sudo scontrol update nodename=picluster-node01 state=resume
```

Confirm SLURM can launch work on it:

```bash
srun -N1 -n4 hostname       # prints picluster-node01 four times
```

---

## Stage 6: Shared storage (NFS)

### 1 On picluster-login (server)

```bash
sudo apt update && sudo apt install -y nfs-kernel-server

# the directory everyone will share, owned by the cluster user
sudo mkdir -p /clusterfs
sudo chown minhcluster:minhcluster /clusterfs
sudo chmod 755 /clusterfs

# export it to the cluster LAN only
echo '/clusterfs 10.0.0.0/24(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports

sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server
```

Check the export is live:

```bash
sudo exportfs -v            # should list /clusterfs for 10.0.0.0/24
```

### 2. On each compute node (client)

Run from picluster-login 

```bash
for h in $NODES; do
  ssh $h "sudo apt update && sudo apt install -y nfs-common && sudo mkdir -p /clusterfs"
  ssh $h "echo 'picluster-login:/clusterfs  /clusterfs  nfs  defaults,_netdev,nofail  0  0' | sudo tee -a /etc/fstab"
  ssh $h "sudo mount -a && df -h /clusterfs"
done
```

### 3. Verify the share works both ways

```bash
# write on the login node...
echo hello > /clusterfs/hello.txt

# ...read it on the compute node
ssh picluster-node01 "cat /clusterfs/hello.txt"   # prints: hello
rm /clusterfs/hello.txt
```

> ✅ **Tested:** the NFS share mounted on all compute nodes.

---

## Stage 7: The Monte Carlo π workload

> 📁 **The finished Monte Carlo π code is in this repo at
> [`benchmarks/pi`](../benchmarks/pi).** It has `pi_montecarlo.py`, the job
> scripts for 1, 2, 4 and 16 ranks, the speedup plotting scripts, and the results
> from this cluster. You can copy the files from there instead of typing them in.

Create the program once on the login node, in the shared directory

```bash
mkdir -p /clusterfs/pi
```

```bash
vim /clusterfs/pi/pi_montecarlo.py
```

Paste the following into `pi_montecarlo.py`, then save with `:wq`:

```python
#!/usr/bin/env python3
"""Monte Carlo estimation of pi, parallelised with MPI (mpi4py).

The total number of samples is FIXED regardless of how many ranks run, so
adding ranks means each rank does less work and the parallel section finishes
sooner. A fixed setup section models the unavoidable serial work in a real
program. Every node pays for it at the same time, so it costs the same
wall-time however many ranks run, which caps the achievable speedup
(a miniature Amdahl's law).

Usage:
    mpirun -n <ranks> python3 pi_montecarlo.py [total_samples]
"""
import sys
import time
import numpy as np
from mpi4py import MPI

SERIAL_WORK  = 5.0          # seconds of unavoidable per-node setup
BATCH        = 2_000_000    # points generated per batch (caps memory use)
DEFAULT_N    = 120_000_000  # total samples if none given on the command line
POLL         = 0.02         # how often a waiting rank checks the barrier


def idle_barrier(comm, poll=POLL):
    """Barrier that leaves waiting ranks idle instead of spinning.

    MPI.Barrier() busy-polls, so a rank sitting in it reads as 100% busy.
    Ibarrier returns immediately and we sleep between checks, so the cores
    of waiting ranks stay genuinely idle.
    """
    req = comm.Ibarrier()
    while not req.Test():
        time.sleep(poll)


def burn_one_core(seconds):
    """Keep exactly one core at full load for the given wall time.

    time.sleep() would hand the CPU back to the scheduler and show as idle,
    which is not what a real serial section looks like. A plain Python loop
    is single-threaded, so this pegs one core and leaves the rest alone.
    """
    deadline = time.monotonic() + seconds
    acc = 0.0
    while time.monotonic() < deadline:
        for i in range(20_000):        # chunked so the clock check is cheap
            acc += i * 0.5
    return acc


comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

total_samples = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_N

# Work out who is on which node, then elect the lowest rank on each node as
# that node's leader. With one rank per node every rank is a leader; with
# four ranks per node only one of the four is.
my_name = MPI.Get_processor_name()
names   = comm.allgather(my_name)
is_node_leader = (rank == min(r for r, n in enumerate(names) if n == my_name))

# Line everyone up, then start the clock.
idle_barrier(comm)
t_start = MPI.Wtime()

# ---- setup section: work the parallel phase must wait for ----
# Each node's leader burns one core, the other ranks wait idle in the barrier
# below. All nodes burn concurrently, so this still costs 5 s of wall time no
# matter how many nodes are in play.
if is_node_leader:
    burn_one_core(SERIAL_WORK)
idle_barrier(comm)
t_parallel = MPI.Wtime()

# ---- parallel section: split the fixed total across the ranks ----
my_samples = total_samples // size
if rank < total_samples % size:        # spread the remainder fairly
    my_samples += 1

rng = np.random.default_rng(rank)      # an independent stream per rank
inside = 0
remaining = my_samples
while remaining > 0:
    n = min(BATCH, remaining)
    x = rng.random(n)
    y = rng.random(n)
    inside += int(np.count_nonzero(x * x + y * y <= 1.0))
    remaining -= n

# Ranks that finish early would otherwise spin inside the reduce below, so
# hold them here first and let the stragglers catch up while they idle.
idle_barrier(comm)

# ---- collect results on rank 0 ----
total_inside = comm.reduce(inside, op=MPI.SUM, root=0)
t_end        = MPI.Wtime()

if rank == 0:
    pi_est       = 4.0 * total_inside / total_samples
    serial_time  = t_parallel - t_start
    compute_time = t_end - t_parallel
    wall_time    = t_end - t_start
    nodes        = len(set(names))
    print(f"pi ~= {pi_est:.6f}, computed in {wall_time:.1f} s "
          f"({compute_time:.1f} s compute + {serial_time:.1f} s serial) "
          f"using {size} rank(s) on {nodes} node(s)")
```

Test it outside SLURM first, directly on the compute node.

```bash
ssh picluster-node01 "cd /clusterfs/pi && mpirun -n 4 python3 pi_montecarlo.py 20000000"
```

**Calibrate the load.**:

```bash
ssh picluster-node01 "cd /clusterfs/pi && mpirun -n 1 python3 pi_montecarlo.py 120000000"
```

---

## Stage 8: Job scripts + the speedup demo

Two batch scripts, identical except for the rank count. 

```bash
vim /clusterfs/pi/pi_1rank.sh
```

Paste the following into `pi_1rank.sh`, then save with `:wq`:

```bash
#!/bin/bash
#SBATCH --job-name=pi-1rank
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/pi/%x-%j.out

export OMP_NUM_THREADS=1
cd /clusterfs/pi
echo "host=$(hostname)  ranks=$SLURM_NTASKS"
mpirun -n "$SLURM_NTASKS" python3 /clusterfs/pi/pi_montecarlo.py
```

```bash
vim /clusterfs/pi/pi_4rank.sh
```

Paste the following into `pi_4rank.sh`, then save with `:wq`:

```bash
#!/bin/bash
#SBATCH --job-name=pi-4rank
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/pi/%x-%j.out

export OMP_NUM_THREADS=1
cd /clusterfs/pi
echo "host=$(hostname)  ranks=$SLURM_NTASKS"
mpirun -n "$SLURM_NTASKS" python3 /clusterfs/pi/pi_montecarlo.py
```

Submit both from the login node:

```bash
cd /clusterfs/pi
sbatch pi_1rank.sh
sbatch pi_4rank.sh
squeue                       # watch them run / finish
```


```bash
cat /clusterfs/pi/pi-1rank-*.out /clusterfs/pi/pi-4rank-*.out
```

**Read the result.** Take the two wall times and compute:

```
speedup     = wall_1rank / wall_4rank
efficiency  = speedup / 4
```

```
first digits of pi: 3.1415926
for sample size 600000000: pi ~= 3.141508, computed in 24.6 s using 4 rank(s) on 1 node(s)
                           pi ~= 3.141589, computed in 42.7 s using 1 rank(s) on 1 node(s)

for sample size 200000000: pi ~= 3.141445, computed in 11.5 s using 4 rank(s) on 1 node(s)
                           pi ~= 3.141537, computed in 17.8 s using 1 rank(s) on 1 node(s)

```
