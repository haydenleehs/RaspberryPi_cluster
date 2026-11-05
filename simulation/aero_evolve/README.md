# Evolve a Wing — Genetic Algorithm on the Pi Cluster

A demo for the Raspberry Pi cluster. Instead of testing every possible wing
(like the brute-force sweep in [`../aero`](../aero)), this one **breeds** wings
with a genetic algorithm. It starts from a population of poor wings, keeps the
best ones, mixes and mutates them, and repeats. After 30 generations it finds a
design almost as good as the best of all 622,545 possibilities, while testing only
about 12 % as many.

Each MPI rank is an **island** with its own population. The islands evolve on
their own and, every few generations, send their best wings to a neighbour. A
live web page shows the best wing, the fitness climbing each generation, and lets
you try to beat the cluster with your own design.

> **Note:** This uses the same simplified teaching model of lift, drag and
> take-off as `../aero`. It is for showing how evolutionary search and parallel
> islands work, not for designing real wings.

---

## Files

| File | Role |
|---|---|
| `aero_evolve.py` | The island-model genetic algorithm (`mpi4py` + `numpy`). |
| `evolve.sh` | SLURM batch script. It launches `aero_evolve.py` with `mpirun` (population 2,400, 30 generations). |
| `evolve.html` | Live web page. It reads `best.json` every second and shows the progress; it also has a "Race the Cluster" panel. |
| `best.json` | Written by rank 0 after **every** generation: the best wing so far plus the fitness history. |
| `evo-16-142.out` | Example SLURM log from a 16-core run. |

---

## What is being evolved

Each wing (the *genome*) is three numbers, the same as in `../aero`:

| Gene | Range | Meaning |
|---|---|---|
| Angle of attack | −5° to 25° | How far the wing is tilted into the air |
| Camber | 0 to 12 % of chord | How curved the aerofoil is |
| Thickness | 4 to 30 % of chord | How thick the aerofoil is |

Values are kept on a 0.25 grid, so every wing the GA can make is also one of the
622,545 designs in the brute-force sweep.

The aircraft is fixed: 1,000 kg, 16 m² wing, 400 m runway. For the lift, drag,
take-off and cruise formulas, see the [`../aero` README](../aero/README.md#how-one-design-is-tested).

### Fitness: how "good" a wing is

```
If the wing takes off:
    fitness = 0.5 × range_km / 1000  +  0.5 × (400 − roll_m) / 400
              └── long range ──┘        └── short take-off ──┘

If it can't take off:
    fitness = −1 + 0.9 × min(1, Cl / 0.8)        (between −1 and −0.1)
```

- Wings that fly are scored half on range and half on short take-off. A
  "perfect" wing (1,000 km range, 0 m roll) would score 1.0.
- Wings that don't fly still get a score, and more lift scores better. This
  gives the GA a slope to climb towards lift-off, instead of every failed wing
  scoring the same.
- The weight `W = 0.5` is set at the top of `aero_evolve.py`. Raise it to favour
  range, or lower it to favour short take-off.

---

## How the genetic algorithm works

Each rank runs this loop on its own island for 30 generations:

1. **Start badly on purpose.** Every island starts near angle 2°, camber 1 %,
   thickness 22 %, with a little random spread. That's a thick, flat wing that
   barely flies, so you can watch the population improve.
2. **Evaluate** every wing on the island (run the take-off and cruise checks).
3. **Report.** All ranks share their top 3 wings and their average fitness.
   Rank 0 keeps the best wing ever seen and writes `best.json`.
4. **Build the next generation:**
   - **Elitism:** the island's 2 best wings survive unchanged.
   - **Migration** (every 3rd generation): the island also takes the 2 best
     wings from the island before it in a ring (rank *r* takes from rank *r−1*).
     Good ideas spread around the cluster without every island becoming the same.
   - **Selection:** each parent is the best of 3 randomly picked wings
     (tournament selection).
   - **Crossover:** each gene of the child is a blend of the two parents, picked
     from slightly beyond the range between them:
     `child = p1 + u·(p2 − p1)`, with `u` random in [−0.15, 1.15].
   - **Mutation:** each gene has a 30 % chance of a random nudge (σ = 1.5° for
     angle, 0.8 % for camber, 1.5 % for thickness).
   - The child is clipped to the allowed ranges and snapped to the 0.25 grid.

### Parallelism

- The **total** population is fixed at 2,400, so each island gets
  `2400 ÷ ranks` wings: 600 per island on 4 ranks, or 150 per island on 16
  ranks. More ranks means less work each, so the run gets faster.
- The ranks sync once per generation (one small `allgather`). Waiting ranks
  sleep in a non-blocking `Ibarrier` instead of busy-waiting, so the per-Pi CPU
  LEDs show only real work.
- Each rank uses its own random seed (`1234 + rank`), so runs are repeatable
  for the same number of ranks.

---

## Results

From `evo-16-142.out` (16 ranks on 4 nodes):

```
evolved 2400 designs x 30 generations in 24.0 s using 16 rank(s) on 4 node(s)
best: angle 8.0°, camber 2.75 %, thickness 4.0 %  →  307 m roll, 884 km range, fitness 0.558
```

**How good is that?** The brute-force sweep in `../aero` tested all 622,545
designs. The best possible design for this fitness lies on that sweep's Pareto
front. Scoring the front gives:

| Design | Roll | Range | Fitness |
|---|---|---|---|
| Best possible: 7.25° / 3.25 % / 4.0 % | 315 m | 905 km | 0.5587 |
| **GA result:** 8.0° / 2.75 % / 4.0 % | 307 m | 884 km | **0.5583** |

The GA found the **second-best design of all 622,545**, within 0.1 % of the
best, using 2,400 × 30 = 72,000 evaluations, which is about 12 % of what the
brute-force sweep needed. That's the point of the demo: smart search versus
checking everything.

The fitness history in `best.json` shows the typical GA shape. The best fitness
jumps from −0.1 (nothing flies) to 0.48 in one generation, then creeps up and
levels off at 0.558 by generation 18. The average follows behind as the whole
population improves.

---

## Setup

### What the cluster needs

The same setup as the other demos in this repo:

- A **SLURM** cluster with a partition called `cluster`.
- A **shared NFS folder at `/clusterfs`** on every node. The scripts use the
  absolute path `/clusterfs/simulation/aero_evolve`.
- **OpenMPI**, **Python 3**, **NumPy** and **mpi4py** on every compute node:

```bash
sudo apt update && sudo apt install -y openmpi-bin python3-numpy python3-mpi4py
```

### 1. Start the web page

`evolve.html` loads `best.json` from the same folder, so it must be served over
HTTP. Double-clicking the file won't work. On the login node:

```bash
cd /clusterfs/simulation/aero_evolve && python3 -m http.server 8000
```

Open `http://<login-node-ip>:8000/evolve.html` (for example
`http://10.0.0.1:8000/evolve.html`). It will say *"Waiting for the cluster…"*
until a job starts.

### 2. Run the evolution

In a second terminal, run it on all four Pis (16 cores):

```bash
sbatch --job-name=evo-16 --nodes=4 --ntasks=16 /clusterfs/simulation/aero_evolve/evolve.sh
```

Or on one Pi (4 cores), to compare the time:

```bash
sbatch --job-name=evo-4 --nodes=1 --ntasks=4 /clusterfs/simulation/aero_evolve/evolve.sh
```

Read the summary when it finishes (`<jobid>` is the number `sbatch` printed):

```bash
cat /clusterfs/simulation/aero_evolve/evo-16-<jobid>.out
```

### Slowing it down for a live demo

At full speed the run finishes in about 24 s, which is quick to watch. The
`PACE` setting makes each generation take at least that many seconds, so the
web page has time to animate:

```bash
sbatch --export=ALL,PACE=1 --job-name=evo-16 --nodes=4 --ntasks=16 /clusterfs/simulation/aero_evolve/evolve.sh
```

With `PACE=1`, the 30 generations take about 30 s or more. Use `PACE=0` (the
default) when you're timing 4 cores against 16.

### Running by hand

```bash
cd /clusterfs/simulation/aero_evolve && mpirun -n 4 python3 aero_evolve.py 0 2400 30
```

The arguments are, in order: `pace_s`, `total_pop` and `generations`.

---

## Suggested demo

1. Open the web page, then submit the job with `PACE=1`.
2. Watch the wing in the wind tunnel change shape and the fitness graph climb.
3. While it runs, use **Race the Cluster** to set your own wing and see whether
   you can beat it. (Hint: very thin, moderately curved wings do well.)
4. Run it again with `PACE=0` on 4 and on 16 cores, and compare the times.
5. Compare with `../aero`: the GA gets within 0.1 % of the brute-force answer
   with about 12 % of the work.

---

## Known caveats

- **Only one run at a time.** Every run writes to the same `best.json`, and
  rank 0 deletes it when a new run starts.
- **The population must divide evenly.** Each island gets `total_pop ÷ ranks`
  wings, rounded down. With 2,400 and 4 or 16 ranks that's exact. With other
  counts, a few wings are lost.
- **Results depend on the number of ranks.** The random seeds and the island
  sizes change with the rank count, so a 4-core run and a 16-core run can find
  slightly different "best" wings. The GA isn't guaranteed to find the true best.
- **Cruise speed leaves out air density**, the same simplification as in
  `../aero` (see that README's caveats).
- The summary prints the best roll distance with many decimal
  places (for example `307.00479550236827`). Only the whole metres matter.
