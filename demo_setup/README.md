# Raspberry Pi HPC Demo Cluster: Build Guide

How this cluster was built: five Raspberry Pi 4B boards (one login node and four
compute nodes) running SLURM and MPI, with shared NFS storage and an 8×8 LED
load display on each compute node.

Follow the parts in order:

| Part | Stages | What it sets up |
|---|---|---|
| [Part 1](Part-1.md) | 0–3 | Flash the SD cards with Raspberry Pi Imager, get the login node online (eduroam Wi-Fi, SSH from a MacBook over Ethernet), and give every compute node a fixed address and name |
| [Part 2](Part-2.md) | 4–5 | Install MPI and Python on every node, then set up the SLURM job scheduler with munge |
| [Part 3](Part-3.md) | 6–8 | Share `/clusterfs` over NFS, then run the Monte Carlo π demo (code in [`benchmarks/pi`](../benchmarks/pi)) |
| [Part 4](Part-4.md) | 9 | Wire up and run the per-node MAX7219 LED load bars (code in [`led`](led)), plus troubleshooting for a node that shows DOWN |
| [Part 5](Part-5-demo-check) | — | Before each demo: run `demo_check.sh` to check every node, SLURM, NFS, a test job and the LEDs in one go |

Files are created with **vim** throughout; Part 1's *Conventions* section
explains the steps.

Once the cluster is running, see [`../simulation`](../simulation) for the demos
and [`../benchmarks`](../benchmarks) for the performance results.
