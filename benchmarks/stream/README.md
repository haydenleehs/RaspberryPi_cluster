# STREAM — Memory Bandwidth

[STREAM](https://www.cs.virginia.edu/stream/) measures how fast a computer can
move data between its CPU and main memory (RAM). Many scientific programs are
limited by this rather than by how fast the CPU can calculate.

It times four simple loops over large arrays (20 million elements each,
about 458 MB in total, far bigger than the CPU caches):

| Kernel | Operation | Bytes moved per element |
|---|---|---|
| **Copy** | `a[i] = b[i]` | 16 |
| **Scale** | `a[i] = q·b[i]` | 16 |
| **Add** | `a[i] = b[i] + c[i]` | 24 |
| **Triad** | `a[i] = b[i] + q·c[i]` | 24 |

The result is the best bandwidth in **MB/s** over 20 repeats.

---

## Results

### One node, 4 threads (`stream-1node-25.out`)

| Kernel | MB/s |
|---|---|
| Copy | 4,175 |
| Scale | 4,385 |
| Add | 4,081 |
| Triad | **4,101** |

The run printed *"Solution Validates"*, so the results are correct.

### All four nodes at once (`stream-all-26.out`)

Each Pi ran STREAM at the same time, independently:

| Node | Copy | Scale | Add | Triad |
|---|---|---|---|---|
| node01 | 4,157 | 4,327 | 4,119 | 4,083 |
| node02 | 4,149 | 4,369 | 4,105 | 4,126 |
| node03 | 4,167 | 4,365 | 4,103 | 4,117 |
| node04 | 4,227 | 4,369 | 4,098 | 4,181 |

All four Pis are within 2.5 % of each other, so no node is slower than the rest.
Each Pi has its own memory, so the cluster's total memory bandwidth is about
**16.5 GB/s** (4 × ~4.1 GB/s).

### Thread sweep on one node (`stream-sweep-27.out`)

| Threads | Copy | Scale | Add | Triad |
|---|---|---|---|---|
| 1 | **5,735** | **5,748** | **5,058** | **5,051** |
| 2 | 5,045 | 4,416 | 4,555 | 4,548 |
| 4 | 4,178 | 4,333 | 4,035 | 4,079 |

**More threads made it slower.** A single core can already use all the memory
bandwidth a Pi has, and adding cores only makes them compete for it. This is
why memory-heavy code doesn't speed up much from 1 to 4 cores on one Pi. The
[`../pi`](../pi) benchmark shows the same effect: its compute part only gets
1.7× faster on 4 cores of one Pi, but 5.3× faster on 16 cores spread over 4 Pis.

---

## Files

| File | Role |
|---|---|
| `stream_c.exe` | Compiled STREAM binary (aarch64, OpenMP) |
| `src/` | STREAM source code (see the note below) |
| `stream_1node.sh` | SLURM script: one node, 4 OpenMP threads |
| `stream_allnodes.sh` | SLURM script: all 4 nodes at once, one copy per node |
| `stream_sweep.sh` | SLURM script: one node with 1, 2 and 4 threads |
| `stream-*.out` | Results from the runs above |

---

## How to run it

The scripts call `/clusterfs/stream/stream_c.exe`.

```bash
sbatch /clusterfs/stream/stream_1node.sh
```

```bash
sbatch /clusterfs/stream/stream_allnodes.sh
```

```bash
sbatch /clusterfs/stream/stream_sweep.sh
```

Each finishes in well under a minute. Results go to
`/clusterfs/stream/<job-name>-<jobid>.out`.

### Rebuilding the binary

From the STREAM source (`stream.c`):

```bash
gcc -O3 -fopenmp -DSTREAM_ARRAY_SIZE=20000000 -DNTIMES=20 stream.c -o /clusterfs/stream/stream_c.exe
```

The array size must be much larger than the CPU cache. 20 million doubles
(about 153 MB per array) is plenty for a Pi.

---

## Note about `src/`

On GitHub, `src/` shows as a folder you can't open. On the Pi it was its own
git repository (the STREAM source was probably downloaded with `git clone`), so
GitHub stored a link to it instead of the files. The source code itself isn't
in this repo. The original is available from the
[STREAM website](https://www.cs.virginia.edu/stream/).
