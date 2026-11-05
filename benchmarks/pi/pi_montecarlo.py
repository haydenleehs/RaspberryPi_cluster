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
