# Wing Storm Simulator — Monte Carlo Aerofoil Turbulence Test

A demo for the Raspberry Pi cluster. It tests one wing (aerofoil) design against
tens of millions of random wind gusts and small manufacturing defects, and
reports how often the wing **flies safely**, **sinks** (not enough lift) or
**stalls**. The work is split across MPI ranks on the cluster, so you can
compare running on one Pi (4 cores) with running on all four Pis (16 cores).

> **Note:** This is a teaching model, not real aerodynamics. The lift, drag and
> stall formulas are simplified linear approximations picked to behave
> plausibly. The point is to show Monte Carlo uncertainty analysis and parallel
> speedup, not to certify a wing.

---

## How the pieces fit together

```
 Browser (turbulence.html)
   │  sliders + "Run" buttons
   │  GET /submit?angle=..&camber=..&thick=..&turb=..&samples=..&ranks=4|16
   ▼
 server.py  (picluster-login, port 8000)
   │  sbatch --nodes=N --ntasks=ranks turbulence.sh <args>
   ▼
 SLURM ──► turbulence.sh ──► mpirun -n $SLURM_NTASKS python3 turbulence_mc.py <args>
                                   │
                                   ▼
                     every rank simulates its share of the samples
                                   │  MPI reduce to rank 0
                                   ▼
                          mc_results.json  ◄── GET /status (polled every 0.6 s)
```

| File | Role |
|---|---|
| `turbulence.html` | Web UI: an animated wind tunnel, the design sliders, the results and the speedup table. |
| `server.py` | A small HTTP server. It serves the UI, submits SLURM jobs (`/submit`) and reports the queue and results (`/status`). |
| `turbulence.sh` | The SLURM batch script. It sets `OMP_NUM_THREADS=1` and launches the MPI job. |
| `turbulence_mc.py` | The Monte Carlo simulation itself (`mpi4py` + `numpy`). |
| `mc_results.json` | Written by rank 0 when a job finishes. The server sets it to `"running"` when it submits a job. |
| `mc-<job>-<id>.out` | SLURM log for each job. |

---

## The inputs

| Parameter | UI slider | Default (script) | Meaning |
|---|---|---|---|
| `angle` | Wing Tilt | 6.0° | Angle of attack: how far the wing is tilted into the oncoming air. |
| `camber` | Wing Curve | 4.0 % | How curved the aerofoil is, as a percentage of chord. |
| `thickness` | Wing Thickness | 12.0 % | Maximum thickness, as a percentage of chord. |
| `turbulence` | Storminess | 2.5 | Scales how strong the random gusts are. |
| `samples` | Random Gusts | 40,000,000 | Total number of Monte Carlo trials. |

The aircraft is fixed: **1,000 kg** (weight W = 9,810 N), **16 m²** wing area,
**50 m/s** cruise speed and sea-level air density ρ = 1.225 kg/m³.

---

## What one Monte Carlo trial does

Each trial is one moment of flight through a random gust, flown by a wing with
slightly random build errors. The script processes trials in vectorised
batches of 1 million.

### 1. Randomise the conditions

Each value is drawn from a normal (Gaussian) distribution around the design value:

| Quantity | Distribution | Represents |
|---|---|---|
| Effective angle | `angle + N(0, 0.8·turbulence)` | Vertical gusts change the angle the air meets the wing |
| Effective camber | `camber + N(0, 0.15)` | Manufacturing tolerance |
| Effective thickness | `thickness + N(0, 0.25)` | Manufacturing tolerance |
| Airspeed | `50 + N(0, 2.2·turbulence)` m/s | Head- and tail-wind gusts |

### 2. Check for stall

The stall angle depends on the shape of the wing. Thicker wings stall later,
and more camber lowers the stall angle a little:

```
stall_angle = 14.5 − 0.12·camber + 0.15·(thickness − 10)
```

The trial is **stalled** if the effective angle is greater than `stall_angle`.

### 3. Lift coefficient

```
Cl = 0.11·angle + 0.09·camber        (linear "thin-aerofoil-like" region)
Cl = 0.35 × that, if stalled         (airflow separates and lift collapses)
```

### 4. Drag coefficient

```
Cd = 0.008 + 0.0004·(thickness − 8)² + 0.04·Cl²     (profile + induced drag)
Cd += 0.18, if stalled                              (separated-flow penalty)
```

### 5. Lift force and the "unsafe drop" check

```
q    = ½ · ρ · V² · S          (dynamic pressure × wing area)
Lift = q · Cl
```

The trial is an **unsafe drop** if the lift is less than **85 % of the
aircraft's weight**, meaning the plane would sink noticeably.

### 6. Tally

Each rank keeps running totals: the number of stalls, the number of unsafe
drops, the sum of Cl, the sum of Cd, and a 25-bin histogram of Cl over 0 to 2.5.

---

## Parallelism (MPI)

- `total_n` samples are split evenly across the ranks. The first
  `total_n % size` ranks take one extra sample each.
- Each rank seeds its own random number generator from its rank and the clock,
  so the random streams are independent.
- No communication happens during the compute loop. The problem is
  *embarrassingly parallel*, so speedup should be close to linear.
- `idle_barrier()` (a non-blocking `Ibarrier` that polls every 20 ms) is used
  before and after the timed section. Idle ranks sleep instead of busy-waiting,
  so the per-Pi CPU LEDs show only real work.
- At the end, `comm.reduce(..., MPI.SUM)` sends all the totals to rank 0.
  Rank 0 computes the percentages and writes `mc_results.json`.
- The 1M-sample batch keeps each rank's memory well under the cluster's
  1.8 GB limit.

The server picks the layout: **4 ranks → 1 node** and **16 ranks → 4 nodes**.

---

## Outputs

`mc_results.json` (written by rank 0):

| Field | Meaning |
|---|---|
| `stall_pct` | Percentage of trials where the gust pushed the wing past its stall angle |
| `drop_pct` | Percentage of trials where lift was less than 85 % of the weight |
| `survival_pct` | `100 − max(stall_pct, drop_pct)` |
| `avg_cl`, `avg_cd` | Mean lift and drag coefficients over all trials |
| `histogram`, `bins` | Distribution of Cl |
| `wall_time` | Seconds between the two barriers (compute plus the final reduce) |
| `ranks`, `nodes`, `samples`, `job_label` | Run metadata |

The UI shows **Safe / Sinking / Stall** as a bar that adds up to 100 %. It also
keeps a table of runs and computes **speedup = 4-core time ÷ 16-core time**
once you have run both.

---

## Running it

```bash
# On picluster-login
python3 /clusterfs/aero_turb/server.py
# then open http://10.0.0.1:8000/turbulence.html
```

To submit a job by hand, without the UI:

```bash
sbatch --nodes=4 --ntasks=16 /clusterfs/aero_turb/turbulence.sh 8.0 4.0 12.0 3.0 40000000 manual
cat /clusterfs/aero_turb/mc_results.json
```

Arguments are positional: `angle camber thickness turbulence samples label`.

**Suggested demo:** keep the default design, run it on 4 cores, then on 16
cores, and compare the times in the speedup table. Then turn Storminess up to
5 or more, or tilt the wing past about 12°, and watch the stall percentage climb.

---

## Known caveats

- **Stall and "sinking" are mostly separate events, but the UI treats stall as
  a subset of sinking.** A stalled wing still makes `0.35 × Cl`, which at
  cruise speed is usually more than 85 % of the weight. So most stalled trials
  are *not* counted as drops, and most drops are low-speed, low-angle trials
  that did not stall. The UI computes `sink = drop_pct − stall_pct` (clamped at
  0), so it under-reports sinking. For example, at 8° in storm level 3, about
  0.18 % of trials sink but the UI shows 0 %. The same assumption sits behind
  `survival_pct = 100 − max(...)`. To get exact categories, count
  `~is_stalled & low_lift` separately in `turbulence_mc.py`.
- Rank 0 always writes the results file to the same path, so only one job's
  results are kept at a time. Running jobs at the same time will overwrite
  each other.
- The wind-tunnel animation in the browser is cosmetic. Its gust is a
  sine-wave approximation and is not linked to the cluster run.
- `/submit` passes its query values straight to `sbatch` (as an argument list,
  not through a shell). The server has no authentication, so keep it on the
  cluster's private network.
