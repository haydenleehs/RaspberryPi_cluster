#!/usr/bin/env python3
"""Brute-force sweep of the aerofoil design space with MPI.
Usage: mpirun -n <ranks> python3 aero_sweep.py [refinement 1,2,3...]"""
import sys, time, json, math, itertools
import numpy as np
from mpi4py import MPI

S, Wt, M0, RUN = 16, 9810, 1000, 400
K = 1 / (math.pi * 6 * .85)

def aero(a, m, t):
    sl = .105 * (1 - .004 * (t - 12))
    cmax = max(.6, .9 + .13 * m + .012 * (t - 12))
    as_ = cmax / sl - .9 * m
    st = a > as_
    cl = max(.3, cmax - .09 * (a - as_)) if st else sl * (a + .9 * m)
    cd = (.005 + .0006 * t + .0003 * m + K * cl * cl
          + ((.02 + .012 * (a - as_)) if st else 0) + .00002 * a * a)
    return cl, cd

def takeoff(cl, cd):
    v = x = tm = 0.0
    while tm < 40:
        q = .5 * 1.225 * v * v * S
        L, D = q * cl, q * cd
        acc = (2600 * (1 - v / 100) - D - .04 * max(Wt - L, 0)) / M0
        v = max(0.0, v + acc * .05); x += v * .05; tm += .05
        if x > RUN or (acc <= 0 and v < 1 and tm > 1): return None
        if L >= Wt: return x
    return None

def cruise(cl, cd):
    if cl <= .1 or math.sqrt(2 * Wt / (S * cl)) > 90: return None
    return round(70 * cl / cd)

def idle_barrier(comm, poll=0.02):
    req = comm.Ibarrier()
    while not req.Test(): time.sleep(poll)

comm = MPI.COMM_WORLD
rank, size = comm.Get_rank(), comm.Get_size()
f = int(sys.argv[1]) if len(sys.argv) > 1 else 1
designs = list(itertools.product(np.arange(-5, 25.001, .25 / f),
                                 np.arange(0, 12.001, .25 / f),
                                 np.arange(4, 30.001, .25 / f)))
mine = designs[rank::size]          # interleaved = balanced load
names = comm.allgather(MPI.Get_processor_name())

idle_barrier(comm); t0 = MPI.Wtime()
out = []
for a, m, t in mine:
    cl, cd = aero(a, m, t)
    d = takeoff(cl, cd)
    if d is None: continue
    r = cruise(cl, cd)
    if r: out.append((round(a, 2), round(m, 2), round(t, 2), round(d), r))
idle_barrier(comm)
allr = comm.gather(out, root=0)
wall = MPI.Wtime() - t0

if rank == 0:
    rows = [r for part in allr for r in part]
    rows.sort(key=lambda r: r[3])
    pareto, best = [], 0
    for r in rows:                  # shorter take-off AND longer range
        if r[4] > best: pareto.append(r); best = r[4]
    maxr = max(r[4] for r in rows)
    allround = max(rows, key=lambda r: r[4] / maxr + 1 - r[3] / RUN)
    json.dump({"designs": len(designs), "flyable": len(rows), "pareto": pareto,
               "sample": rows[::max(1, len(rows) // 2000)],
               "shortest": rows[0], "longest": max(rows, key=lambda r: r[4]),
               "allrounder": allround}, open("/clusterfs/simulation/aero/results.json", "w"))
    print(f"swept {len(designs)} designs, {len(rows)} can fly, in {wall:.1f} s "
          f"using {size} rank(s) on {len(set(names))} node(s)")
    print("shortest take-off:", rows[0], "(angle, camber, thick, roll m, range km)")
    print("longest range:    ", max(rows, key=lambda r: r[4]))
    print("best all-rounder: ", allround)
