# Raspberry Pi HPC Cluster

A small **high-performance computing (HPC) cluster** built from five Raspberry
Pi 4B boards. It works like a real supercomputer, just much smaller: jobs are
submitted to a **SLURM** scheduler, run in parallel across the Pis with **MPI**,
and read and write a shared **NFS** folder. An 8×8 LED matrix on each compute
node shows its CPU load live, so you can *see* the work spread across the cluster.

It's built for teaching and demos: showing how parallel computing works, how
much faster more cores make a job, and where the limits are.

---

## The hardware

```
                eduroam Wi-Fi (internet)
                          │
                ┌─────────┴──────────┐
                │  picluster-login   │  10.0.0.1   SLURM controller, NFS server,
                │                    │             shares internet with the nodes
                └─────────┬──────────┘
                          │ Ethernet
                 ┌────────┴────────┐
                 │  Gigabit switch │
                 └─┬─────┬─────┬─┬─┘
         ┌─────────┘   ┌─┘     └┐ └──────────┐
   ┌─────┴─────┐ ┌─────┴─────┐ ┌┴──────────┐ ┌┴──────────┐
   │  node01   │ │  node02   │ │  node03   │ │  node04   │   compute nodes
   │ 10.0.0.2  │ │ 10.0.0.3  │ │ 10.0.0.4  │ │ 10.0.0.5  │   4 cores each
   │ [LED: C]  │ │ [LED: S]  │ │ [LED: C]  │ │ [LED: N]  │   16 cores in total
   └───────────┘ └───────────┘ └───────────┘ └───────────┘
```

| Part | Details |
|---|---|
| Boards | 5 × Raspberry Pi 4B: 1 login node + 4 compute nodes (4 cores at 1.8 GHz each) |
| Network | Gigabit Ethernet switch; private LAN `10.0.0.0/24` |
| Software | Raspberry Pi OS Lite (64-bit), SLURM + munge, OpenMPI, Python 3 with NumPy and mpi4py, NFS |
| Displays | 4 × MAX7219 8×8 LED matrices, one per compute node. When idle they spell **NSCC**; under load each shows one bar per CPU core. |

---

## What's in this repo

| Folder | What's inside |
|---|---|
| [`demo_setup/`](demo_setup) | **Start here to build the cluster.** A step-by-step guide in 5 parts: flashing the SD cards, networking, SLURM, NFS, the π demo, the LED displays, and a pre-demo health check script. |
| [`simulation/`](simulation) | **Demos** with interactive web pages: wing (aerofoil) design by brute-force search, by genetic algorithm, and a Monte Carlo turbulence test. |
| [`benchmarks/`](benchmarks) | **Performance measurements:** HPL (compute), STREAM (memory), OSU (network) and a Monte Carlo π speedup test, with the results from this cluster. |

Every folder has its own README with details, results and how to run it.

---

## Highlights

| What | Result | Where |
|---|---|---|
| Compute speed (HPL) | **57.1 GFLOPS** on 16 cores; 3.45× faster than 1 Pi | [`benchmarks/hpl`](benchmarks/hpl) |
| Brute-force wing search | 622,545 designs tested in **66.8 s** on 16 cores, vs 270 s on 4 cores (**4.0×** faster) | [`simulation/aero`](simulation/aero) |
| Genetic algorithm | Found the **2nd-best of 622,545** wing designs with about 12 % of the work | [`simulation/aero_evolve`](simulation/aero_evolve) |
| Amdahl's law | A fixed 5 s serial step limits the π demo to **1.9×** faster on 16 cores | [`benchmarks/pi`](benchmarks/pi) |
| Network | **32 µs** latency and **117.6 MB/s** between Pis (full gigabit speed) | [`benchmarks/osu`](benchmarks/osu) |
| Memory | About **4.1 GB/s** per Pi; one core can already use almost all of it | [`benchmarks/stream`](benchmarks/stream) |

**What they show together:** the cluster is great at jobs that split into
independent pieces (like the wing searches), which get close to 4× faster on
4× the Pis. Jobs limited by a serial step, memory bandwidth or network traffic
speed up much less. That's the core lesson of parallel computing.

---

## Quick start

If the cluster is already built, log in to the login node, then:

**1. Check everything is ready:**
```bash
./demo_check.sh
```
It should end with **READY FOR DEMO**. See
[Part 5](demo_setup/Part-5-demo-check) for details and `--fix`.

**2. Run a demo**, for example the wing design sweep on all 16 cores:
```bash
sbatch --job-name=aero-16 --nodes=4 --ntasks=16 /clusterfs/aero/aero.sh
```

**3. Watch the LED matrices** switch from **NSCC** to load bars while it runs,
then read the result:
```bash
cat /clusterfs/aero/aero-16-*.out
```

Compare with one Pi (`--nodes=1 --ntasks=4`) to see the speedup.

To build the cluster from scratch, follow [`demo_setup/`](demo_setup) from Part 1.

---

## Paths on the cluster vs this repo

On the cluster, every project lives directly in the shared folder `/clusterfs`,
and the scripts use those paths. This repo groups them into folders:

| In this repo | On the cluster |
|---|---|
| `simulation/aero`, `simulation/aero_evolve`, `simulation/aero_turb` | `/clusterfs/aero`, `/clusterfs/aero_evolve`, `/clusterfs/aero_turb` |
| `benchmarks/hpl`, `benchmarks/osu`, `benchmarks/pi`, `benchmarks/stream` | `/clusterfs/hpl`, `/clusterfs/osu`, `/clusterfs/pi`, `/clusterfs/stream` |
| `demo_setup/led` | `/clusterfs/led` |
| `demo_setup/Part-5-demo-check/demo_check.sh` | `~/demo_check.sh` on the login node |

To copy a project back onto a cluster, copy its folder into `/clusterfs`, for example:

```bash
cp -r simulation/aero /clusterfs/
```
