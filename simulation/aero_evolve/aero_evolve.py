#!/usr/bin/env python3
"""Island-model genetic algorithm that evolves an aerofoil with MPI.
Each rank is an island; the TOTAL population is fixed, so more ranks = less work each.
Usage: mpirun -n <ranks> python3 aero_evolve.py [pace_s=0] [total_pop=2400] [generations=30]
pace_s > 0 slows each generation so the web page can animate (use 0 when timing)."""
import sys, time, json, math, os
import numpy as np
from mpi4py import MPI

S, Wt, M0, RUN = 16, 9810, 1000, 400
K = 1 / (math.pi * 6 * .85)
LO, HI, SIG = np.array([-5, 0, 4.]), np.array([25, 12, 30.]), np.array([1.5, .8, 1.5])
W = 0.5                      # fitness weight: range vs short take-off
OUT = "/clusterfs/aero_evolve/best.json"

def aero(a, m, t):
    sl = .105 * (1 - .004 * (t - 12))
    cmax = max(.6, .9 + .13 * m + .012 * (t - 12))
    as_ = cmax / sl - .9 * m
    st = a > as_
    cl = max(.3, cmax - .09 * (a - as_)) if st else sl * (a + .9 * m)
    cd = (.005 + .0006 * t + .0003 * m + K * cl * cl
          + ((.02 + .012 * (a - as_)) if st else 0) + .00002 * a * a)
    return cl, cd

def evaluate(g):
    cl, cd = aero(*g)
    v = x = tm = 0.0
    ok = False
    while tm < 40:
        q = .5 * 1.225 * v * v * S
        L, D = q * cl, q * cd
        acc = (2600 * (1 - v / 100) - D - .04 * max(Wt - L, 0)) / M0
        v = max(0.0, v + acc * .05); x += v * .05; tm += .05
        if x > RUN or (acc <= 0 and v < 1 and tm > 1): break
        if L >= Wt: ok = True; break
    if not ok:
        return -1 + .9 * min(1, max(0, cl / .8)), None, None
    V = math.sqrt(2 * Wt / (S * cl))
    rg = round(70 * cl / cd) if (cl > .1 and V <= 90) else 0
    return W * rg / 1000 + (1 - W) * (RUN - x) / RUN, x, rg

def idle_barrier(comm, poll=0.02):
    req = comm.Ibarrier()
    while not req.Test(): time.sleep(poll)

comm = MPI.COMM_WORLD
rank, size = comm.Get_rank(), comm.Get_size()
pace  = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0
total = int(sys.argv[2]) if len(sys.argv) > 2 else 2400
gens  = int(sys.argv[3]) if len(sys.argv) > 3 else 30
n = total // size
rng = np.random.default_rng(1234 + rank)
# start every island from poor, similar wings so the climb to a good design is visible
pop = np.clip(np.array([2., 1., 22.]) + rng.normal(0, 1, (n, 3)) * np.array([1.5, .8, 2.5]), LO, HI)
nodes = len(set(comm.allgather(MPI.Get_processor_name())))
best_hist, mean_hist, best = [], [], None

def write(gen, done, wall):
    doc = {"gen": gen, "gens": gens, "ranks": size, "nodes": nodes, "w": W,
           "done": done, "wall": wall,
           "best": {"a": best[1][0], "m": best[1][1], "t": best[1][2],
                    "dist": best[2], "range": best[3], "fit": best[0]},
           "best_hist": best_hist, "mean_hist": mean_hist}
    json.dump(doc, open(OUT + ".tmp", "w")); os.replace(OUT + ".tmp", OUT)

if rank == 0 and os.path.exists(OUT): os.remove(OUT)
idle_barrier(comm); t0 = MPI.Wtime()
for gen in range(1, gens + 1):
    g0 = time.time()
    res = [evaluate(g) for g in pop]
    fit = np.array([r[0] for r in res])
    order = np.argsort(-fit)
    top = [(float(fit[i]), pop[i].tolist(), res[i][1], res[i][2]) for i in order[:3]]
    idle_barrier(comm)                       # waiting ranks stay idle, not spinning
    info = comm.allgather((top, float(fit.mean())))
    if rank == 0:
        b = max((c for tp, _ in info for c in tp), key=lambda c: c[0])
        if best is None or b[0] >= best[0]: best = b
        best_hist.append(round(best[0], 4))
        mean_hist.append(round(sum(m for _, m in info) / size, 4))
        write(gen, gen == gens, round(MPI.Wtime() - t0, 2) if gen == gens else None)
    new = [pop[i] for i in order[:2]]        # elites survive
    if gen % 3 == 0:                         # migration: best of the neighbouring island
        new += [np.array(c[1]) for c in info[(rank - 1) % size][0][:2]]
    while len(new) < n:
        pick = lambda: pop[(lambda ix: ix[np.argmax(fit[ix])])(rng.integers(0, n, 3))]
        p1, p2 = pick(), pick()
        c = p1 + rng.uniform(-.15, 1.15, 3) * (p2 - p1)
        c += (rng.random(3) < .3) * rng.normal(0, 1, 3) * SIG
        new.append(np.round(np.clip(c, LO, HI) * 4) / 4)
    pop = np.array(new[:n])
    rem = pace - (time.time() - g0)
    if rem > 0: time.sleep(rem)

if rank == 0:
    wall = MPI.Wtime() - t0
    print(f"evolved {total} designs x {gens} generations in {wall:.1f} s "
          f"using {size} rank(s) on {nodes} node(s)")
    print("best (angle, camber, thickness, roll m, range km, fitness):",
          best[1], best[2], best[3], round(best[0], 3))
