# Simulations

Aerofoil (wing) demos for the Raspberry Pi cluster. They all use SLURM + MPI and
live in `/clusterfs/` on the cluster.

| Folder | What it does |
|---|---|
| [`aero`](aero) | **Brute-force sweep.** Tests all 622,545 wing designs to find which can take off from a 400 m runway and how far each can fly, plus an interactive "design a wing" web page. |
| [`aero_evolve`](aero_evolve) | **Genetic algorithm.** Breeds wings across MPI "islands" and gets within 0.1 % of the brute-force best with about 12 % of the work. Has a live web page. |
| [`aero_turb`](aero_turb) | **Monte Carlo turbulence test.** Flies one wing through tens of millions of random gusts and reports how often it is safe, sinks or stalls. |

Each folder has its own README with setup steps.

> On GitHub these folders are grouped under `simulation/`, but on the cluster
> they sit directly in `/clusterfs` (`/clusterfs/aero`, `/clusterfs/aero_evolve`,
> `/clusterfs/aero_turb`). The scripts use those cluster paths.
