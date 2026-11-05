#!/usr/bin/env python3
"""Monte Carlo Aerofoil Turbulence & Uncertainty Simulation (MPI).

Tests a single aerofoil design against tens of millions of random atmospheric
gusts and manufacturing tolerances across the cluster cores.
"""
import sys
import time
import json
import numpy as np
from mpi4py import MPI

BATCH = 1_000_000   # 1M samples per batch (keeps RAM well under 1800MB limit)
POLL  = 0.02        # sleep interval for idle barrier so LEDs stay accurate

def idle_barrier(comm, poll=POLL):
    req = comm.Ibarrier()
    while not req.Test():
        time.sleep(poll)

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# Read parameters passed from SLURM script
angle      = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0
camber     = float(sys.argv[2]) if len(sys.argv) > 2 else 4.0
thickness  = float(sys.argv[3]) if len(sys.argv) > 3 else 12.0
turbulence = float(sys.argv[4]) if len(sys.argv) > 4 else 2.5
total_n    = int(sys.argv[5])   if len(sys.argv) > 5 else 40_000_000
job_label  = sys.argv[6]        if len(sys.argv) > 6 else f"{size}ranks"

my_name = MPI.Get_processor_name()
names   = comm.allgather(my_name)

idle_barrier(comm)
t_start = MPI.Wtime()

# Split samples across MPI ranks
my_samples = total_n // size
if rank < total_n % size:
    my_samples += 1

# Independent random number stream per core
rng = np.random.default_rng(rank + int(time.time() * 100) % 10000)

stalls = 0
unsafe_drops = 0
lift_sum = 0.0
drag_sum = 0.0
hist_bins = np.linspace(0.0, 2.5, 26)
local_hist = np.zeros(25, dtype=np.int64)

# Physics constants (1,000 kg aircraft, 16 m^2 wing, 50 m/s cruise)
W = 9810.0  # Weight in Newtons
rho = 1.225
S = 16.0
V0 = 50.0

remaining = my_samples
while remaining > 0:
    n = min(BATCH, remaining)
    
    # Generate random gusts & manufacturing micro-defects
    eff_angle  = angle + rng.normal(0.0, turbulence * 0.8, n)
    eff_camber = camber + rng.normal(0.0, 0.15, n)
    eff_thick  = thickness + rng.normal(0.0, 0.25, n)
    eff_V      = V0 + rng.normal(0.0, turbulence * 2.2, n)
    
    # Critical stall angle decreases if wing is too thin or overly cambered
    stall_angle = 14.5 - 0.12 * eff_camber + 0.15 * (eff_thick - 10.0)
    is_stalled  = eff_angle > stall_angle
    
    # Calculate Lift Coefficient (Cl)
    cl_normal = 0.11 * eff_angle + 0.09 * eff_camber
    cl = np.where(is_stalled, cl_normal * 0.35, cl_normal)
    
    # Calculate Drag Coefficient (Cd)
    cd_base = 0.008 + 0.0004 * (eff_thick - 8.0)**2 + 0.04 * (cl**2)
    cd = np.where(is_stalled, cd_base + 0.18, cd_base)
    
    # Dynamic pressure and actual Lift force
    q = 0.5 * rho * (eff_V**2) * S
    lift_force = q * cl
    
    stalls += int(np.count_nonzero(is_stalled))
    unsafe_drops += int(np.count_nonzero(lift_force < W * 0.85)) # <85% weight support
    lift_sum += float(np.sum(cl))
    drag_sum += float(np.sum(cd))
    
    h, _ = np.histogram(cl, bins=hist_bins)
    local_hist += h
    
    remaining -= n

idle_barrier(comm)

# Gather results to Rank 0
total_stalls = comm.reduce(stalls, op=MPI.SUM, root=0)
total_drops  = comm.reduce(unsafe_drops, op=MPI.SUM, root=0)
total_lift   = comm.reduce(lift_sum, op=MPI.SUM, root=0)
total_drag   = comm.reduce(drag_sum, op=MPI.SUM, root=0)
total_hist   = comm.reduce(local_hist, op=MPI.SUM, root=0)
t_end        = MPI.Wtime()

if rank == 0:
    wall_time = t_end - t_start
    nodes = len(set(names))
    stall_pct = (total_stalls / total_n) * 100.0
    drop_pct  = (total_drops / total_n) * 100.0
    survival_pct = 100.0 - max(stall_pct, drop_pct)
    
    result = {
        "status": "complete",
        "job_label": job_label,
        "ranks": size,
        "nodes": nodes,
        "samples": total_n,
        "wall_time": round(wall_time, 2),
        "stall_pct": round(stall_pct, 3),
        "drop_pct": round(drop_pct, 3),
        "survival_pct": round(survival_pct, 3),
        "avg_cl": round(total_lift / total_n, 3),
        "avg_cd": round(total_drag / total_n, 4),
        "histogram": total_hist.tolist(),
        "bins": [round(x, 2) for x in hist_bins[:-1]]
    }
    
    with open("/clusterfs/aero_turb/mc_results.json", "w") as f:
        json.dump(result, f)
        
    print(f"[{job_label}] Survival: {survival_pct:.2f}% | Stall Risk: {stall_pct:.2f}% | "
          f"Time: {wall_time:.2f}s ({size} ranks on {nodes} nodes)")
