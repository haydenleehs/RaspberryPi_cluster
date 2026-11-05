# Part 5: Demo Check — Pre-Demo Health Check

[`demo_check.sh`](demo_check.sh) checks the whole cluster in one go before a
demo: every node, SLURM, munge, the NFS share, the π demo files, a real test
job, and the LED displays. It prints **PASS / WARN / FAIL** for each check and
ends with either **READY FOR DEMO** or **NOT READY**.

With `--fix`, it also tries the standard fixes from the guide's troubleshooting
section (resuming nodes, restarting services, remounting NFS).

---

## Usage

Run it on **picluster-login** as `minhcluster`. First copy it from this folder
to the login node's home folder (skip this if `~/demo_check.sh` is already there):

```bash
cp ~/RaspberryPi_cluster/demo_setup/Part-5-demo-check/demo_check.sh ~/
```

Then make it executable, from your home folder:

```bash
cd ~ && chmod +x demo_check.sh
```

| Command | What it does | Time |
|---|---|---|
| `./demo_check.sh` | Run every check and report only. Changes nothing except the test job (see the warning below). | up to ~2.5 min |
| `./demo_check.sh --fix` | Run the checks and try to fix what fails, then check again. | up to ~2.5 min |
| `./demo_check.sh --quick` | Skip the `sbatch` test job (step 4b). | a few seconds |
| `./demo_check.sh --help` | Show the usage lines. | |

`--fix` and `--quick` can be combined:

```bash
./demo_check.sh --fix --quick
```

To check a different set of nodes, set `NODES` first:

```bash
NODES="picluster-node01 picluster-node02" ./demo_check.sh
```

---

## What it checks

| Step | Checks | With `--fix` |
|---|---|---|
| **0. Reachability** | Each compute node answers over SSH (5 s timeout, no password prompt). | |
| **1. SLURM up** | `slurmctld` is running on the login node, and `sinfo` shows every node as `idle`. Nodes in any other state are reported with SLURM's reason. | A node that's *not responding* gets `slurmd` restarted. A node that's `down` or `drain` gets `scontrol update ... state=resume`. Then it checks again. |
| **1b. Node services** | On each node: `slurmd` and `munge` are running; the node finds its own `10.0.0.x` address in `/etc/hosts`; its clock is within 5 s of the login node (WARN if not). Also checks that a munge credential made on a node is accepted on the login node, which shows the `munge.key` files match. | |
| **2. Shared filesystem** | `/clusterfs` is mounted over NFS on each node, and a file written on the login node can be read on a node. | Runs `sudo mount -a` on nodes where it isn't mounted. |
| **3. Demo files** | `/clusterfs/pi` exists with `pi_montecarlo.py`, a 4-rank job script and a 1-rank script (WARN if missing). | |
| **4. SLURM test** | `srun -N1 -n4 hostname` returns 4 lines, and `srun -N4 -n4 hostname` reaches all 4 nodes. | |
| **4b. Test job** | Submits the 4-rank π job with `sbatch`, waits up to 120 s, and checks that the output has a π result and no errors. Cancels the job if it's still running. Skipped with `--quick`. | |
| **5. LED displays** | The `led-load` service is running on each node. | Restarts `led-load`; if it still fails, shows the last 5 lines of its log. |

The 4-rank job script is the first one found from: `pi-4rank-test.sh`,
`pi_4rank_test.sh`, `pi-4rank.sh`, `pi_4rank.sh`.

---

## Reading the result

On a healthy cluster the full run ends like this:

```
== Summary ==
  42 passed, 1 warnings, 0 failed

READY FOR DEMO
```

The 1 warning is expected: `/clusterfs` on the login node is the NFS export
folder itself, not a mount, so step 2 reports *"login: /clusterfs is not a
mountpoint (OK if it is the export dir)"*. With `--quick` there are 2 fewer
passes, because the test job and its cleanup are skipped.

If anything failed, each failure is listed again under the summary, followed by
**NOT READY** and a hint to try `--fix`.

| Exit code | Meaning |
|---|---|
| `0` | No failures: ready for the demo (warnings are allowed) |
| `1` | At least one check failed |
| `2` | Unknown command-line option |

If `--fix` doesn't clear a failure, work through
[Part 4 → Troubleshooting](../Part-4.md#troubleshooting-a-node-shows-down-after-power-on).

---

## Requirements

These are all set up by the build guide:

- **Run on picluster-login**, where `sinfo`, `srun`, `sbatch` and `slurmctld` are.
- **Passwordless SSH** to every node ([Part 1](../Part-1.md), Stage 3). The script
  uses `BatchMode`, so a node that asks for a password counts as unreachable.
- **Passwordless sudo** ([Part 2](../Part-2.md)) for the `--fix` actions on the
  nodes, and for `scontrol` on the login node.
- The π demo in `/clusterfs/pi` ([Part 3](../Part-3.md)) and the `led-load`
  service on each node ([Part 4](../Part-4.md)).

---

## ⚠️ Warning: the test job deletes `.out` files

After the step 4b test job, the script runs:

```bash
rm -f /clusterfs/pi/*.out
```

This deletes **every** `.out` file in `/clusterfs/pi`, not just the test job's
output. That includes saved results such as `pi-1rank-210.out` and
`pi-16rank-212.out`.

To keep your results, do one of these:
- Run with `--quick`, which skips the test job and the cleanup.
- Copy the results somewhere safe first:
  ```bash
  mkdir -p ~/pi_results && cp /clusterfs/pi/*.out ~/pi_results/
  ```
- Note that the results from this cluster are already saved on GitHub in
  [`benchmarks/pi`](../../benchmarks/pi).
