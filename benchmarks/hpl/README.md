# HPL — High-Performance Linpack

HPL is the benchmark behind the [TOP500](https://www.top500.org/) supercomputer
list. It builds a large random matrix *A*, solves the dense linear system
**Ax = b** with LU factorisation spread across all MPI ranks, checks that the
answer is correct, and reports the speed in **GFLOPS** (billions of
floating-point operations per second).

This folder has HPL 2.3 built for the Pi cluster against OpenBLAS, plus run
folders for 1, 2 and 4 nodes.

---

## Results

| Nodes | Ranks | Grid P×Q | N (matrix size) | NB | Time | **GFLOPS** | Speedup |
|---|---|---|---|---|---|---|---|
| 1 | 4 | 1×4 | 19,584 | 96 | 303.0 s | **16.53** | 1.00× |
| 2 | 8 | 2×4 | 27,840 | 96 | 460.6 s | **31.23** | 1.89× |
| 4 | 16 | 4×4 | 38,688 | 96 | 676.3 s | **57.09** | 3.45× |

All runs **passed** HPL's residual check, so the answers are correct.

- **Scaling efficiency on 4 nodes is 86 %** (57.09 ÷ (4 × 16.53)). The rest is
  lost to communication over gigabit Ethernet (see [`../osu`](../osu)).
- Each run uses a matrix sized to fill about 75 % of RAM (about 3 GB per Pi).
  A bigger problem keeps the cores busy computing for longer between network
  messages.

### Tuning on one node

Several single-node runs tried different block sizes (NB) and process grids:

| Job | N | NB | P×Q | GFLOPS |
|---|---|---|---|---|
| 34 | 19,584 | 96 | 1×4 | **16.53** (best) |
| 35 | 19,584 | 96 | 1×4 | 16.50 |
| 42 | 19,456 | 128 | 2×2 | 15.93 |
| 43 | 19,600 | 196 | 2×2 | 15.82 |
| 44 | 19,456 | 256 | 2×2 | 15.68 |
| 39 | 11,760 | 196 | 2×2 | 15.31 |
| 37 | 11,776 | 128 | 2×2 | 14.93 |
| 40 | 11,776 | 256 | 2×2 | 14.83 |

Takeaways:
- **Bigger N helps.** About 19,500 beats about 11,800 by roughly 0.6–1 GFLOPS.
- On one node, a **1×4 grid with NB = 96** was best.
- The `HPL.dat` now in `hpl_1node/` is the **last** configuration tried
  (N = 19,456, NB = 256, 2×2), not the best one. To reproduce 16.53 GFLOPS, set
  N = 19584, NB = 96, P = 1, Q = 4.

### Temperature monitoring

The 1-node runs also logged the CPU temperature and clock every 2 s
(`monitor_picluster-node01_<job>.log`):

- Peak temperature was **68.7 °C**.
- The clock stayed at **1,800 MHz** under load.
- `throttled = 0x0` throughout, so **no thermal throttling** happened.

The results reflect full-speed CPUs.

The earlier 2-node (job 31) and 4-node (job 32) runs were made before their
scripts had monitoring, so they have no temperature logs. All three scripts now
start the logger (see [Monitoring temperature, clock and throttling](#monitoring-temperature-clock-and-throttling)).

---

## Files

```
hpl/
├── hpl-2.3.tar.gz         original HPL source download
├── hpl-2.3/               unpacked source + build
│   ├── Make.rpi           build config for the Pi (mpicc, -O3 -mcpu=native, OpenBLAS)
│   └── bin/rpi/xhpl       the compiled benchmark
├── templog.sh             temperature / clock / throttle logger (every 2 s)
├── hpl_thermal_summary.py summarises a run's GFLOPS with its temperature / clock / throttle logs
├── hpl_1node/             1 node,  4 ranks: HPL.dat, hpl-1node.sh, outputs, monitor logs
├── hpl_2node/             2 nodes, 8 ranks: HPL.dat, hpl-2node.sh, output
└── hpl_4node/             4 nodes, 16 ranks: HPL.dat, hpl-4node.sh, output
```

Each run folder has its own copy of `xhpl` and an `HPL.dat` input file. The
SLURM script writes `hosts.txt` (4 slots per node) and runs
`mpirun --hostfile hosts.txt ./xhpl`.

---

## How to run it

### 1. Install the dependencies (every node)

```bash
sudo apt update && sudo apt install -y build-essential openmpi-bin libopenmpi-dev libopenblas-dev
```

### 2. Build HPL (once, on the shared filesystem)

`Make.rpi` expects the source at `/clusterfs/hpl/hpl-2.3`:

```bash
cd /clusterfs/hpl && tar xzf hpl-2.3.tar.gz && cd hpl-2.3
```

```bash
make arch=rpi
```

This creates `bin/rpi/xhpl`. Copy it into each run folder:

```bash
for d in 1 2 4; do cp bin/rpi/xhpl /clusterfs/hpl/hpl_${d}node/; done
```

### 3. Submit a run

```bash
sbatch /clusterfs/hpl/hpl_4node/hpl-4node.sh
```

Use `hpl_1node/hpl-1node.sh` or `hpl_2node/hpl-2node.sh` for the smaller runs.
Each script already requests the right number of nodes, with `--exclusive` so
no other job shares the Pis.

The 4-node run takes about **11–12 minutes**. Check the result:

```bash
grep -A2 "^T/V" /clusterfs/hpl/hpl_4node/hpl-4node-<jobid>.out
```

### Run 1, 2 and 4 nodes in one go

This submits all three runs; each waits for the previous one to finish
(about 25 minutes in total):

```bash
cd /clusterfs/hpl && j1=$(sbatch --parsable hpl_1node/hpl-1node.sh) && j2=$(sbatch --parsable --dependency=afterany:$j1 hpl_2node/hpl-2node.sh) && j3=$(sbatch --parsable --dependency=afterany:$j2 hpl_4node/hpl-4node.sh) && echo "jobs: $j1 $j2 $j3"
```

Because they run back to back, the 2-node and 4-node runs start on warm Pis.
Submit them one at a time, a few minutes apart, if you want each to start cool.

### Choosing N in `HPL.dat`

Use about 75–80 % of the total RAM across the nodes in the run:

```
N ≈ sqrt(0.75 × total_RAM_bytes / 8)
```

Round it down to a multiple of NB. Pick P × Q = number of ranks, with P ≤ Q
and as square as possible.

---

## Monitoring temperature, clock and throttling

All three scripts (`hpl-1node.sh`, `hpl-2node.sh`, `hpl-4node.sh`) record how
hot the Pis get and whether they slow down during HPL:

- Before HPL starts, the script launches [`templog.sh`](templog.sh) on **every
  node in the job** (with `srun --overlap`). Every 2 seconds it records the CPU
  temperature, the clock speed, and the throttle status from
  `vcgencmd get_throttled`.
- Each node writes its own `monitor_<node>_<jobid>.log` into the run folder:
  1 log for a 1-node run, 2 for 2 nodes, 4 for 4 nodes.
- The script waits 10 s before and after HPL, so the logs show the idle
  temperature and the cool-down too. The loggers stop when the job ends.

Example log lines:

```
time host temp_C scaling_MHz arm_clock_MHz throttled
16:08:47 picluster-node01 32.1 1800 1800 0x0
16:08:49 picluster-node01 32.6 1800 1800 0x0
```

### Summarising a run

[`hpl_thermal_summary.py`](hpl_thermal_summary.py) puts each run's GFLOPS
together with its logs. For every node it shows the temperature before the
run, the peak and average temperature and clock speed **during the HPL solve**,
and any throttle flags in plain English:

```bash
cd /clusterfs/hpl && python3 hpl_thermal_summary.py hpl_1node/hpl-1node-<j1>.out hpl_2node/hpl-2node-<j2>.out hpl_4node/hpl-4node-<j3>.out
```

With no arguments, it summarises every run in `/clusterfs/hpl/hpl_*node/`.
Real output for 1-node job 35:

```
hpl-1node-35.out   job 35   picluster-node01   4 ranks
  N=19584  NB=96  P×Q=1×4  time=303.5 s  -> 16.50 GFLOPS  [PASSED]
  solve window: 12:03:09 -> 12:08:13
  node                before    peak     avg   avg clk   min clk  throttle
  picluster-node01     33.1C   68.2C   64.8C   1800 MHz  1800 MHz  none (0x0)
  verdict: no throttling: CPUs ran at full speed
```

| Column | Meaning |
|---|---|
| `before` | Temperature when logging started, before HPL ran |
| `peak` / `avg` | Hottest and average temperature during the solve |
| `avg clk` / `min clk` | CPU clock during the solve; 1,800 MHz is full speed |
| `throttle` | `none (0x0)` is good; otherwise the raw code and what it means (under-voltage, frequency capped, throttled, soft temperature limit) |

If any node throttles, the verdict says so. HPL can only run as fast as its
slowest node, so one hot Pi lowers the whole result.

---

## Notes

- The monitoring needs `vcgencmd` (part of Raspberry Pi OS) on every compute
  node. Check with
  `ssh picluster-node01 "vcgencmd measure_temp; vcgencmd get_throttled"`.
- `hpl-1node-34.out` starts with a `Permission denied, please try again.`
  line. That's an SSH login message from that run; the benchmark itself
  completed and passed.
- The `xhpl` binaries are built with `-mcpu=native` for the Pi's ARM CPU
  (aarch64). They won't run on a PC; rebuild on the target machine.
