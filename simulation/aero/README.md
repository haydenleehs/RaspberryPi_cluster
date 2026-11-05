# Design an Aerofoil — Brute-Force Wing Design Sweep

A demo for the Raspberry Pi cluster. It asks a simple question about a small
aircraft's wing:

> **Can it take off from a 400 m runway, and how far can it fly on a full tank?**

The answer depends on three shape settings of the wing's cross-section (the
*aerofoil*). This project has two parts:

1. **An interactive web page** where you move sliders to shape one wing, then
   watch an animated plane try to take off and cruise with it.
2. **A cluster job** (`aero_sweep.py`) that tests *every* combination of the
   three settings (622,545 designs), finds the ones that fly, and picks the best
   trade-offs between short take-off and long range. The work is split across
   MPI ranks, so you can compare one Pi (4 cores) with all four Pis (16 cores).

> **Note:** This is a teaching model, not real aerodynamics. The lift, drag and
> thrust formulas are simplified approximations picked to behave plausibly. It
> is for intuition and for showing parallel speedup, not for building real wings.

---

## Files

| File | Role |
|---|---|
| `aerofoil_simulator.html` | Full web UI: a wind-tunnel view of the wing with lift and drag arrows, sliders, stats, and an animated runway take-off and cruise with sound effects. |
| `aerofoil.html` | A simpler, lighter version of the same page (no sound, fewer panels). |
| `aero_sweep.py` | The brute-force design sweep (`mpi4py` + `numpy`). It uses the same physics as the web pages. |
| `aero.sh` | SLURM batch script. It sets `OMP_NUM_THREADS=1` and launches `aero_sweep.py` with `mpirun`. |
| `results.json` | Written by rank 0 at the end of a sweep: every flyable design (sampled), the Pareto front and the winners. |
| `aero-4-80.out`, `aero-16-81.out` | Example SLURM logs from a 4-core run and a 16-core run. |

The web pages and the cluster job are **independent**. The pages compute
everything in the browser and don't need the cluster.

---

## The three design inputs

| Slider | Range (step 0.25) | Meaning |
|---|---|---|
| **Angle of attack** | −5° to 25° | How far the wing is tilted into the oncoming air. More angle gives more lift, until the wing stalls. |
| **Curvature (camber)** | 0 to 12 % of chord | How curved (arched) the aerofoil is. More camber gives more lift but also more drag. |
| **Thickness** | 4 to 30 % of chord | How thick the aerofoil is. Thicker wings stall later but have more drag. |

The wing shape drawn on screen is a NACA 4-series aerofoil (max camber at 40 %
chord) built from these values.

The aircraft is fixed: **1,000 kg** (weight W = 9,810 N), **16 m²** wing area,
wing aspect ratio 6, sea-level air density ρ = 1.225 kg/m³, and a **400 m** runway.

---

## How one design is tested

### 1. Lift and drag coefficients

```
lift slope   = 0.105 × (1 − 0.004·(thickness − 12))        per degree
Cl_max       = max(0.6,  0.9 + 0.13·camber + 0.012·(thickness − 12))
stall angle  = Cl_max / lift slope − 0.9·camber

Not stalled:  Cl = lift slope × (angle + 0.9·camber)
Stalled:      Cl = max(0.3,  Cl_max − 0.09·(angle − stall angle))     lift collapses

Cd = 0.005 + 0.0006·thickness + 0.0003·camber      (profile drag)
   + Cl² / (π · 6 · 0.85)                           (induced drag)
   + 0.00002·angle²
   + 0.02 + 0.012·(angle − stall angle)             (only if stalled)
```

### 2. Take-off run

The plane starts at rest and is stepped forward in time every 0.05 s:

```
thrust   = 2600 × (1 − v/100)  N           propeller thrust falls with speed
lift     = ½ρv²S · Cl
drag     = ½ρv²S · Cd
friction = 0.04 × (weight − lift)          rolling resistance on the wheels
accel    = (thrust − drag − friction) / 1000 kg
```

- **Lift-off** happens when lift ≥ weight. The distance travelled is the
  *take-off roll*.
- The design **fails** if it runs past 400 m, gets stuck (can't accelerate),
  or hasn't lifted off after 40 s.

### 3. Cruise range

```
cruise speed needed = √(2W / (S·Cl))       must be ≤ 90 m/s
range (km)          = 70 × Cl/Cd           better lift-to-drag ratio → further on a full tank
```

A design with Cl ≤ 0.1 can't hold level flight and gets no range.

### 4. Verdict in the web page

| Result | Verdict |
|---|---|
| Stalled | "Stalled: reduce the angle" |
| No lift-off within 400 m | "Can't get off the runway" |
| Roll < 260 m and range ≥ 900 km | **All-rounder** |
| Roll < 260 m | Short-field specialist |
| Range ≥ 900 km | Long-range cruiser |
| Otherwise | Average design |

---

## The cluster sweep (`aero_sweep.py`)

1. **Build the grid.** Every combination of angle × camber × thickness in steps
   of 0.25: 121 × 49 × 105 = **622,545 designs**.
2. **Split the work.** Rank *r* takes designs `r, r+size, r+2·size, …`
   (interleaved). Hard and easy designs are spread evenly, so all ranks finish
   at about the same time.
3. **Test each design.** Run the take-off and cruise checks above. Keep the
   designs that both take off and cruise.
4. **Gather to rank 0.** No communication happens during the compute loop, so
   the problem is *embarrassingly parallel*. Ranks wait with a sleeping
   `Ibarrier` (not a busy-wait), so the per-Pi CPU LEDs show only real work.
5. **Pick the winners** (rank 0):
   - **Shortest take-off** and **longest range**.
   - **Pareto front:** designs where no other design has *both* a shorter
     take-off *and* a longer range. These are the best possible trade-offs.
   - **Best all-rounder:** maximises `range/max_range + (1 − roll/400)`.
6. **Write `results.json`** and print a summary.

### Results from the cluster

| Run | Ranks | Nodes | Time |
|---|---|---|---|
| `aero-4-80` | 4 | 1 | 270.0 s |
| `aero-16-81` | 16 | 4 | 66.8 s |

**Speedup: 270.0 ÷ 66.8 ≈ 4.0×** with 4× the cores, which is close to perfect
linear scaling. Both runs give the same answer: **253,776 of 622,545 designs can fly.**

| Winner | Angle | Camber | Thickness | Take-off roll | Range |
|---|---|---|---|---|---|
| Shortest take-off | 11.25° | 12 % | 5.75 % | 188 m | 454 km |
| Longest range | 6.0° | 2.25 % | 4 % | 400 m | 1,087 km |
| Best all-rounder | 8.0° | 3.5 % | 4 % | 290 m | 839 km |

The trade-off is clear: lots of camber and angle gets you off the ground fast
but burns fuel, while a thin, gently curved wing goes much further but needs the
whole runway.

### `results.json` format

Each design is stored as `[angle, camber, thickness, roll_m, range_km]`.

| Field | Meaning |
|---|---|
| `designs` | Number of designs tested |
| `flyable` | Number that took off and can cruise |
| `pareto` | The Pareto front, sorted by take-off roll |
| `sample` | About 2,000 flyable designs, evenly sampled (for plotting) |
| `shortest`, `longest`, `allrounder` | The winning designs |

---

## Setup

### What the cluster needs

The scripts expect the same setup as the other demos in this repo:

- A **SLURM** cluster with a partition called `cluster` (a login node plus 4
  compute Pis, 4 cores each).
- A **shared NFS folder at `/clusterfs`**, mounted at the same path on every node.
  The scripts use the absolute path `/clusterfs/aero`.
- **OpenMPI**, **Python 3**, **NumPy** and **mpi4py** installed on **every
  compute node**.

### 1. Install the dependencies (on every compute node)

```bash
sudo apt update && sudo apt install -y openmpi-bin python3-numpy python3-mpi4py
```

Check that MPI works across all nodes:

```bash
srun --nodes=4 --ntasks=16 python3 -c "from mpi4py import MPI; print(MPI.COMM_WORLD.Get_rank(), MPI.Get_processor_name())"
```

You should see ranks 0–15 spread over 4 hostnames.

### 2. Put the files in `/clusterfs/aero`

If you're setting up from GitHub on a new cluster:

```bash
git clone https://github.com/haydenleehs/RaspberryPi_cluster.git /tmp/rpc && cp -r /tmp/rpc/simulation/aero /clusterfs/
```

### 3. Run the sweep

Run it on one Pi (4 cores):

```bash
sbatch --job-name=aero-4 --nodes=1 --ntasks=4 /clusterfs/aero/aero.sh
```

Then on all four Pis (16 cores):

```bash
sbatch --job-name=aero-16 --nodes=4 --ntasks=16 /clusterfs/aero/aero.sh
```

Watch the queue, then read the log once the job finishes. `<jobid>` is the
number `sbatch` printed:

```bash
squeue
```

```bash
cat /clusterfs/aero/aero-16-<jobid>.out
```

The log is named `<job-name>-<jobid>.out`, and the full results go to
`/clusterfs/aero/results.json`.

To run without SLURM (for example, a quick test on one Pi):

```bash
cd /clusterfs/aero && mpirun -n 4 python3 aero_sweep.py 1
```

The number at the end is the **refinement**. `1` uses steps of 0.25. `2` halves
the step (0.125), which gives about 4.9 million designs and takes roughly 8×
longer. `aero.sh` always uses `1`; edit its last line to change it.

### 4. Open the web page

The pages run entirely in the browser, so you can just double-click
`aerofoil_simulator.html` on any computer. To serve them from the cluster to
other devices on the network:

```bash
cd /clusterfs/aero && python3 -m http.server 8000
```

Then open `http://<login-node-ip>:8000/aerofoil_simulator.html` (for example
`http://10.0.0.1:8000/aerofoil_simulator.html`).

**Suggested demo:** start with the defaults and press *Fly this design*. Then
raise the angle until the wing stalls, and try the cluster's winners (for
example 8° / 3.5 % / 4 % for the all-rounder) to see them fly.

---

## Known caveats

- **Cruise speed leaves out air density.** The check uses `√(2W/(S·Cl))`, but
  the real formula is `√(2W/(ρ·S·Cl))`. At sea level this overstates the
  cruise speed by about 10 %, so the 90 m/s limit is slightly stricter than intended. The web
  pages use the same formula, so they still agree with the sweep.
- **Every rank builds the full design list** before taking its share. That's
  about 50 MB per rank at refinement 1, and roughly 400 MB per rank at
  refinement 2, which is around 1.6 GB per Pi with 4 ranks. Check your Pis'
  memory before running refinement 2.
- The printed summary shows values like `np.float64(11.25)`. This is just how
  newer NumPy versions print numbers; the values in `results.json` are plain numbers.
- Rank 0 always writes to the same `results.json`, so running two sweeps at
  the same time makes them overwrite each other.
- The animations in the web pages are for show. The take-off roll and range
  numbers are what the model actually calculates.
