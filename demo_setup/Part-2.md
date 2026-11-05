# Raspberry Pi HPC Demo Cluster Build Guide - Part 2

Make loops below simpler

```bash
NODES="picluster-node01 picluster-node02 picluster-node03 picluster-node04"
```

Make loops don't stop for a password

```bash
echo "minhcluster ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/010-cluster
sudo chmod 440 /etc/sudoers.d/010-cluster
```

---

## Stage 4: MPI + Python (all nodes)

Same packages on every node:

```bash
sudo apt update && sudo apt install -y openmpi-bin python3-mpi4py python3-numpy
for h in $NODES; do ssh $h "sudo apt update && sudo apt install -y openmpi-bin python3-mpi4py python3-numpy"; done
```

---

## Stage 5: SLURM

1. controller + client on login, slurmd + client on compute:

   ```bash
   sudo apt install -y slurmctld slurm-client munge
   for h in $NODES; do ssh $h "sudo apt install -y slurmd slurm-client munge"; done
   ```

2. One shared munge key generated on login, push to every node:

   ```bash
   sudo dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key
   sudo chown munge:munge /etc/munge/munge.key && sudo chmod 400 /etc/munge/munge.key
   sudo install -m 644 /etc/munge/munge.key /tmp/munge.key

   for h in $NODES; do
     scp /tmp/munge.key $h:/tmp/munge.key
     ssh $h "sudo install -o munge -g munge -m 400 /tmp/munge.key /etc/munge/munge.key && rm /tmp/munge.key"
   done
   rm /tmp/munge.key

   sudo systemctl enable --now munge
   for h in $NODES; do ssh $h "sudo systemctl enable --now munge"; done
   ```

   Restart munge and check cross-node auth should end with `STATUS: Success`:

   ```bash
   sudo systemctl restart munge
   for h in $NODES; do ssh $h "sudo systemctl restart munge"; done
   ```
   
   ```bash
   ssh picluster-node01 "munge -n" | unmunge
   ```

3. Write `/etc/slurm/slurm.conf` on login, then copy it unchanged to every node.

```bash
sudo mkdir -p /etc/slurm
```

```bash
sudo vim /etc/slurm/slurm.conf
```

Paste the following into `slurm.conf`, then save with `:wq`:

```ini
ClusterName=picluster
SlurmctldHost=picluster-login

AuthType=auth/munge
SlurmUser=slurm
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log

ProctrackType=proctrack/linuxproc
TaskPlugin=task/none
SelectType=select/cons_tres
SelectTypeParameters=CR_Core
ReturnToService=2

NodeName=picluster-node0[1-4] CPUs=4 RealMemory=1800 State=UNKNOWN
PartitionName=cluster Nodes=ALL Default=YES MaxTime=INFINITE State=UP
```

```bash
sudo install -m 644 /etc/slurm/slurm.conf /tmp/slurm.conf
for h in $NODES; do
  scp /tmp/slurm.conf $h:/tmp/slurm.conf
  ssh $h "sudo mkdir -p /etc/slurm && sudo cp /tmp/slurm.conf /etc/slurm/slurm.conf && rm /tmp/slurm.conf"
done
rm /tmp/slurm.conf
```

4. Create the spool/log dirs and start the daemons:

   ```bash
   # controller (login)
   sudo mkdir -p /var/spool/slurmctld /var/log/slurm
   sudo chown slurm:slurm /var/spool/slurmctld /var/log/slurm
   sudo systemctl enable --now slurmctld

   # compute
   for h in $NODES; do
     ssh $h "sudo mkdir -p /var/spool/slurmd /var/log/slurm && sudo chown slurm:slurm /var/log/slurm && sudo systemctl enable --now slurmd"
   done
   ```

5. Verify:

   ```bash
   sinfo                    # partition 'cluster' with 4 idle nodes
   srun -N4 -n4 hostname    # prints the four node names
   ```

> ✅ **Tested:** SLURM was installed and configured successfully with these
> steps.
