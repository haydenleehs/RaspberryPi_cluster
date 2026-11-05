# Raspberry Pi HPC Demo Cluster Build Guide

A five-node Raspberry Pi 4B cluster running a SLURM-scheduled MPI job
to show parallel speedup, with a per-node 8×8 LED load display.

## Conventions
- Login user: `minhcluster` on every node.
- LAN `10.0.0.0/24`: `picluster-login`=.1, `picluster-node01`=.2, `node02`=.3, `node03`=.4, `node04`=.5.
- Files are created and edited with **vim**. When a step says `vim <file>`:
  1. Run the command to open the file.
  2. Type `:set paste` and press Enter, so pasted code keeps its indentation
     (important for Python files).
  3. Press `i` to start typing, then paste the lines shown.
  4. Press `Esc`, then type `:wq` and press Enter to save and quit.

---

## Stage 0: Flash Raspberry Pi OS 

Flash one microSD card per Pi (5 in total) with **Raspberry Pi Imager**.

1. Download and install Raspberry Pi Imager on your computer from
   <https://www.raspberrypi.com/software/>.
2. Insert a microSD card and open Imager.
3. **Choose Device:** Raspberry Pi 4.
4. **Choose OS:** Raspberry Pi OS (other) → **Raspberry Pi OS Lite (64-bit)**.
5. **Choose Storage:** your microSD card.
6. Click **Next**, then **Edit Settings** to customise the OS:
   - **Hostname:** `picluster-login` for the login node, or `picluster-node01`
     to `picluster-node04` for the compute nodes
   - **Username:** `minhcluster`, plus a password
   - **Services** tab: **Enable SSH** → *Use password authentication*
7. Click **Save**, then **Yes** to apply the settings, then **Yes** to write the card.
8. Label the card with its hostname, then repeat for the next Pi. Only the
   hostname changes between cards.

---

## Stage 1: Login node online + remote access

On picluster-login:

Enable Wi-Fi via raspi-config:

```bash
sudo raspi-config
# Localisation Options → WLAN Country → country = SG.
```

Connect to wifi connection, if using eduroam then with nmtui:

```bash
sudo nmtui
```

Edit a connection → Add → Wi-Fi, then set:

- Profile name `eduroam`, SSID `eduroam`
- Security: WPA & WPA2 Enterprise
- Authentication: PEAP
- Inner authentication: MSCHAPv2
- Username `<your-id>@<institution>`, Password: your institution password

OK → Back → Activate a connection → `eduroam` → Activate. Then:

```bash
ping -c 3 deb.debian.org        # internet + DNS
```

IP forwarding:

```bash
echo 'net.ipv4.ip_forward = 1'          | sudo tee /etc/sysctl.d/99-cluster.conf
sudo sysctl -p /etc/sysctl.d/99-cluster.conf
```

### Remote access from a MacBook over Ethernet

eduroam blocks direct remote access, so connect to the login node with an
Ethernet cable instead:

1. Connect the login Pi's Ethernet port to the MacBook with a cable (use a
   USB/Thunderbolt Ethernet adapter if the Mac has no Ethernet port).
2. On the Mac: **System Settings → General → Sharing → Internet Sharing**.
   Share the connection from **Wi-Fi** to the Ethernet adapter, then turn
   Internet Sharing on.
3. SSH into the Pi from the Mac:

```bash
ssh minhcluster@picluster-login.local
```

---

## Stage 2: Login node shares internet to the cluster

On picluster-login:

```bash
# find the exact 90-NM file name first
ls /etc/netplan/
sudo rm -f /etc/netplan/90-NM-*.yaml
sudo nmcli connection delete netplan-eth0

sudo nmcli connection add type ethernet ifname eth0 con-name cluster-lan \
    ipv4.method shared ipv4.addresses 10.0.0.1/24 ipv6.method disabled \
    connection.autoconnect yes
sudo nmcli connection up cluster-lan
``` 

---

## Stage 3: Address and name the compute nodes

0. On picluster-login, make the SSH key and add the host map locally:

```bash
ssh-keygen -t ed25519 -C cluster -f ~/.ssh/id_ed25519 -N ""
sudo touch /etc/cloud/cloud-init.disabled
sudo vim /etc/hosts
```

Add these lines to the end of `/etc/hosts`, then save with `:wq`:

```
# Pi cluster
10.0.0.1   picluster-login
10.0.0.2   picluster-node01
10.0.0.3   picluster-node02
10.0.0.4   picluster-node03
10.0.0.5   picluster-node04
```

1. On picluster-login:

```bash
sudo cat /var/lib/NetworkManager/dnsmasq-eth0.leases
```

Note the compute node's temporary IP (3rd column).

2. SSH to the node with its temporary IP and set the address directly,
   repeating per node with its own IP. Replace `10.0.0.X` with the node's
   address (node01 → `10.0.0.2`, node02 → `10.0.0.3`, and so on):

```bash
# find the exact 90-NM file name first
ls /etc/netplan/
sudo rm -f /etc/netplan/90-NM-*.yaml
sudo nmcli connection delete netplan-eth0

sudo nmcli connection add type ethernet ifname eth0 con-name cluster \
    ipv4.method manual ipv4.addresses 10.0.0.X/24 ipv4.gateway 10.0.0.1 \
    ipv4.dns "10.0.0.1 8.8.8.8" ipv6.method disabled connection.autoconnect yes
sudo nmcli connection up cluster
```

3. Give it the host map. Still on the compute node:

```bash
sudo touch /etc/cloud/cloud-init.disabled
sudo vim /etc/hosts
```

Add the same lines as on the login node, then save with `:wq`:

```
# Pi cluster
10.0.0.1   picluster-login
10.0.0.2   picluster-node01
10.0.0.3   picluster-node02
10.0.0.4   picluster-node03
10.0.0.5   picluster-node04
```

4. On the login node, copy the key:

```bash
ssh-copy-id minhcluster@10.0.0.X
```

5. Verify from picluster-login:

```bash
ping -c 2 10.0.0.X
ssh picluster-node0X hostname        # prints picluster-node0X, no password
```

Then go back to step 1 for the next node (node02 → .3, and so on). 

> ✅ **Tested:** all four compute nodes were set up this way, and each one
> could be reached with `ssh picluster-node0X` without a password.
