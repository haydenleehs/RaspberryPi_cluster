# OSU Micro-Benchmarks — Network Latency and Bandwidth

The [OSU Micro-Benchmarks](https://mvapich.cse.ohio-state.edu/benchmarks/)
(version 7.5) measure how fast MPI can send messages between processes. Here
they test the **gigabit Ethernet network** between the Pis: how long a tiny
message takes (*latency*), how much data per second a big message can carry
(*bandwidth*), and how fast group operations across all 4 nodes are
(*collectives*).

Every run places **one rank per node**, so all traffic goes over the network,
not through shared memory inside one Pi. The scripts set
`OMPI_MCA_btl_tcp_if_include=eth0` to force MPI onto the cluster's wired LAN.

---

## Results

### Point-to-point: node01 ↔ node02 (`osu-pt2pt-22.out`, `osu-pt2pt-28.out`)

| Message size | Latency | Bandwidth |
|---|---|---|
| 1 B | **31.7 µs** | 0.05 MB/s |
| 1 KB | 51.3 µs | 50.6 MB/s |
| 4 KB | 102.7 µs | 110.1 MB/s |
| 64 KB | 765 µs | 112.0 MB/s |
| 1 MB | 9.2 ms | 117.3 MB/s |
| 4 MB | 36.0 ms | **117.6 MB/s** |

- **Latency is about 32 µs** for small messages. That's the minimum cost of
  any message between Pis.
- **Bandwidth peaks at 117.6 MB/s**, which is about 940 Mbit/s, essentially
  the full speed of gigabit Ethernet.
- Bandwidth reaches its maximum from about **4 KB** messages upwards.
  Smaller messages are dominated by latency.
- The two runs (jobs 22 and 28) agree within 1 %, so the results are stable.

**Bidirectional bandwidth** (both sides sending at once) reaches up to
about **232 MB/s** for 8–32 KB messages, which is both directions of gigabit running
at full speed. For messages of 64 KB and above it drops back to about
**117 MB/s**, the same as one direction. So large two-way transfers don't
get the full-duplex benefit on this setup.

### Every pair of nodes (`osu-pairs-24.out`)

1 MB bandwidth between every pair of nodes:

| | node02 | node03 | node04 |
|---|---|---|---|
| **node01** | 117.27 | 117.29 | 117.30 |
| **node02** | | 117.26 | 117.27 |
| **node03** | | | 117.28 |

All six links are the same, within 0.04 MB/s. There are no bad cables or slow
switch ports.

### Collectives: all 4 nodes (`osu-coll-23.out`)

| Operation | Small message | 1 KB | 1 MB |
|---|---|---|---|
| Barrier (sync all ranks) | **98 µs** | | |
| Allreduce (sum across all ranks) | 83 µs | 109 µs | 18.3 ms |
| All-to-all (everyone sends to everyone) | 93 µs | 112 µs | 36.0 ms |

Any operation that synchronises the whole cluster costs at least about **0.1 ms**.
That's why the demos in `simulation/` avoid communicating inside their main
loops.

---

## Files

| File | Role |
|---|---|
| `osu_pt2pt.sh` | SLURM: 2 nodes; `osu_latency`, `osu_bw`, `osu_bibw` over all message sizes |
| `osu_pairs.sh` | SLURM: 4 nodes; 1 MB `osu_bw` between every pair of nodes |
| `osu_coll.sh` | SLURM: 4 nodes; `osu_barrier`, `osu_allreduce`, `osu_alltoall` (1 B – 1 MB) |
| `osu-*.out` | Results from the runs above |
| `libexec/osu-micro-benchmarks/mpi/` | The compiled benchmark programs |
| `osu-micro-benchmarks-7.5/` | The OSU source code and build files |

---

## How to run it

### 1. Build (once)

```bash
sudo apt update && sudo apt install -y build-essential openmpi-bin libopenmpi-dev
```

```bash
cd /clusterfs/osu/osu-micro-benchmarks-7.5 && ./configure CC=mpicc CXX=mpicxx --prefix=/clusterfs/osu && make -j4 && make install
```

This installs the programs into `/clusterfs/osu/libexec/osu-micro-benchmarks/mpi/`,
which is where the scripts look for them.

### 2. Run

```bash
sbatch /clusterfs/osu/osu_pt2pt.sh
```

```bash
sbatch /clusterfs/osu/osu_pairs.sh
```

```bash
sbatch /clusterfs/osu/osu_coll.sh
```

Results go to `/clusterfs/osu/<job-name>-<jobid>.out`.

If your cluster's network interface isn't called `eth0`, change
`OMPI_MCA_btl_tcp_if_include` in the scripts. Check the name with `ip -br addr`.
