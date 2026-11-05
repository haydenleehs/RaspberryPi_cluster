# Raspberry Pi HPC Demo Cluster Build Guide - Part 4 (LED setup)


Setup runs from `picluster-login`:

```bash
NODES="picluster-node01 picluster-node02 picluster-node03 picluster-node04"
```

---

## Stage 9: Per-node LED load display (MAX7219)

### 1. Wire one matrix to each compute node

| MAX7219 pin | Pi header pin | Function      |
|-------------|---------------|---------------|
| VCC         | 2             | 5V            |
| GND         | 9             | Ground        |
| DIN         | 19            | GPIO10 / MOSI |
| CS          | 24            | GPIO8 / CE0   |
| CLK         | 23            | GPIO11 / SCLK |


### 2. Enable SPI and install the driver package (all compute nodes)

```bash
for h in $NODES; do
  ssh $h "sudo raspi-config nonint do_spi 0 && sudo dtparam spi=on"
  ssh $h "sudo apt update && sudo apt install -y python3-spidev"
done
```

Check the device exists:
```bash
for h in $NODES; do ssh $h "ls /dev/spidev0.0"; done   # one line per node
```

### 3. The display program

> 📁 **The LED files are in this repo at [`demo_setup/led`](led):**
> [`led_load.py`](led/led_load.py) and [`led-load.service`](led/led-load.service).
> You can copy them to `/clusterfs/led/` instead of typing them in.
>
> The `led_load.py` in that folder is a **newer version** than the one below.
> When the cluster is idle, each matrix shows a letter so the four boards spell
> **NSCC**, with a breathing glow, a shimmer sweep across the letters, and a
> wipe animation when switching between the letter and the load bars. When a
> job runs, the boards switch to the per-core load bars. The program below is
> the simpler bars-only version.
>
> If you use the newer version, check these settings at the top of the file:
> - `LETTER_FOR`: which letter each node shows.
> - `POSITION`: the left-to-right order of the boards.
> - `ROTATE`: set to `2` for this build's mounting.

Write it once on the login node, in the shared directory:

```bash
mkdir -p /clusterfs/led
```

```bash
vim /clusterfs/led/led_load.py
```

Paste the following into `led_load.py`, then save with `:wq`:

```python
#!/usr/bin/env python3
"""Four vertical bars on a MAX7219 8x8 matrix, one bar per CPU core.

Each core owns two columns. Bar height tracks that core's utilisation
over the last sampling interval, read from /proc/stat. Readings are
smoothed with an exponential moving average so sub-second blips (like
MPI process startup) barely register, while sustained load shows at
full height. Runs forever; clears the display on exit.
"""
import signal
import sys
import time

import spidev

INTERVAL  = 0.2   # seconds between samples
BRIGHT    = 4     # 0 (dim) .. 15 (blinding); keep low, it is plenty
ROTATE    = 0     # 0/1/2/3 = quarter turns, adjust to your module's mounting
SMOOTH    = 0.5   # 0 = raw readings, closer to 1 = smoother/slower

spi = spidev.SpiDev()
spi.open(0, 0)                # bus 0, CE0
spi.max_speed_hz = 1_000_000

def cmd(reg, val):
    spi.xfer2([reg, val])

def init_display():
    cmd(0x0F, 0x00)           # display-test off
    cmd(0x09, 0x00)           # no BCD decode, raw bits
    cmd(0x0B, 0x07)           # scan all 8 digits
    cmd(0x0A, BRIGHT)         # intensity
    cmd(0x0C, 0x01)           # leave shutdown mode
    clear()

def clear():
    for d in range(8):
        cmd(d + 1, 0x00)

def rotate(fb):
    for _ in range(ROTATE):
        fb = [sum(((fb[7 - c] >> (7 - r)) & 1) << (7 - c) for c in range(8))
              for r in range(8)]
    return fb

def show(fb):                 # fb = 8 row-bytes, fb[0] is the top row
    fb = rotate(fb)
    for r in range(8):
        cmd(r + 1, fb[r])

def read_cores():
    """Return {'cpu0': (busy, total), ...} in jiffies."""
    out = {}
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("cpu") and line[3].isdigit():
                p = line.split()
                idle  = int(p[4]) + int(p[5])          # idle + iowait
                total = sum(int(x) for x in p[1:8])
                out[p[0]] = (total - idle, total)
    return out

def bar_frame(loads):
    """loads = per-core fractions 0..1 -> 8 row-bytes, bars rise from the bottom."""
    heights = [round(l * 8) for l in loads]
    fb = []
    for row in range(8):                               # row 0 = top
        byte = 0
        for core, h in enumerate(heights[:4]):
            if h >= 8 - row:                           # bar tall enough to reach this row
                byte |= 0b11 << (6 - 2 * core)         # two columns per core
        fb.append(byte)
    return fb

def shutdown(*_):
    clear()
    cmd(0x0C, 0x00)
    spi.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

init_display()
prev = read_cores()
ema  = [0.0] * len(prev)
while True:
    time.sleep(INTERVAL)
    cur = read_cores()
    loads = []
    for cpu in sorted(prev):
        db = cur[cpu][0] - prev[cpu][0]
        dt = cur[cpu][1] - prev[cpu][1]
        loads.append(db / dt if dt > 0 else 0.0)
    ema = [SMOOTH * e + (1 - SMOOTH) * l for e, l in zip(ema, loads)]
    show(bar_frame(ema))
    prev = cur
```

Test it by hand on one node before making it a service:

```bash
ssh picluster-node01 "sudo python3 /clusterfs/led/led_load.py"
```

From a second terminal, load it:

```bash
ssh picluster-node01 "cd /clusterfs/pi && mpirun -n 4 python3 pi_montecarlo.py 60000000"
```

### 4. Install as a service (all compute nodes)

The service copies the script to local disk and starts at boot with no manual step on demo day.

```bash
vim /clusterfs/led/led-load.service
```

Paste the following into `led-load.service`, then save with `:wq`:

```ini
[Unit]
Description=MAX7219 CPU load bars

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/led_load.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

```bash
for h in $NODES; do
  ssh $h "sudo install -m 755 /clusterfs/led/led_load.py /usr/local/bin/led_load.py"
  ssh $h "sudo install -m 644 /clusterfs/led/led-load.service /etc/systemd/system/led-load.service"
  ssh $h "sudo systemctl daemon-reload && sudo systemctl enable --now led-load"
done
```

### 5. Verify

```bash
for h in $NODES; do ssh $h "systemctl is-active led-load"; done   # four lines: active
```

Then the end-to-end demo check, from the login node:

```bash
cd /clusterfs/pi
sbatch pi_4rank.sh
```

---

## Troubleshooting: a node shows DOWN after power-on

After starting the Pis, a node (here `picluster-node04`) can show as `down` in
`sinfo`. Work through these checks from the login node, replacing `node04`
and `10.0.0.5` with the node in question.

### 1. Is the node reachable?

```bash
ping -c 2 10.0.0.5
```

```bash
ssh picluster-node04 hostname
```

If the ping fails, the node hasn't booted or its Ethernet link is down. Check
the cable and the link lights, and power-cycle it if needed. Then wait about a
minute and check again.

### 2. Is slurmd running on it?

```bash
ssh picluster-node04 "systemctl is-active slurmd munge"
```

You should see two `active` lines. If either isn't active, restart them:

```bash
ssh picluster-node04 "sudo systemctl restart munge && sudo systemctl restart slurmd"
```

### 3. Why does SLURM say it's down?

```bash
sinfo -R
```

The reason column usually says `Not responding` (the node was unreachable) or
`Node unexpectedly rebooted`.

### 4. Bring it back

```bash
sudo scontrol update nodename=picluster-node04 state=resume
```

```bash
sleep 10 && sinfo
```

The node should now show `idle`.
