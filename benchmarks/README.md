# Benchmarks

Standard HPC benchmarks run on the 4-node Raspberry Pi cluster
(`picluster-node01`–`04`, 4 cores each, 16 cores in total) with SLURM and
OpenMPI. Each one measures a different part of the machine:

| Folder | Measures | Headline result |
|---|---|---|
| [`hpl`](hpl) | **Compute:** how fast the cluster solves a huge system of linear equations (the TOP500 benchmark). | **57.1 GFLOPS** on 4 nodes, 3.5× one node |
| [`stream`](stream) | **Memory bandwidth:** how fast one Pi can move data to and from RAM. | **~4.1 GB/s** per Pi (Triad, 4 threads) |
| [`osu`](osu) | **Network:** latency and bandwidth between Pis over Ethernet. | **~32 µs** latency, **117.5 MB/s** bandwidth |
| [`pi`](pi) | **Parallel speedup:** a Monte Carlo estimate of π, showing Amdahl's law. | **1.9×** on 16 cores (capped by a fixed serial step) |

Together they explain the cluster's behaviour. Each Pi computes well, but its
memory bandwidth is limited and the gigabit network between Pis is much slower
than memory. Jobs that mostly compute (like HPL or the `simulation/` demos)
scale well across nodes, while jobs that move a lot of data scale less well.

On the cluster these folders sit directly in `/clusterfs` (`/clusterfs/hpl`,
`/clusterfs/stream`, `/clusterfs/osu`, `/clusterfs/pi`), and the scripts use
those paths. On GitHub they are grouped under `benchmarks/`.

Each folder has its own README with what was run, the results, and how to run
it again.
