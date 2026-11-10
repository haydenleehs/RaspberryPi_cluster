#!/usr/bin/env bash
# picluster — automated pre-demo check (run on picluster-login)
# See demo_setup/Part-5-demo-check/README.md for what each check does.
#
# Usage:  ./demo_check.sh            # check only
#         ./demo_check.sh --fix      # check + attempt the README's fixes
#         ./demo_check.sh --quick    # skip the sbatch job (step 4b)
#
# The Pis have no RTC: each boots on its last saved clock (days old) and only
# corrects it once NTP is reachable. If slurmd starts first, munge rejects the
# controller ("Rewound credential") and the node goes down*. --fix resyncs
# clocks now and installs a boot guard so slurmd waits for / restarts after sync.

set -u

NODES="${NODES:-picluster-node01 picluster-node02 picluster-node03 picluster-node04}"
PI_DIR="/clusterfs/pi"
SBATCH_TIMEOUT=120          # seconds to wait for the test job
MAX_SKEW=5                  # seconds of node-vs-login clock skew tolerated
FIX=0; QUICK=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    --quick) QUICK=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $a"; exit 2 ;;
  esac
done

SSH="ssh -o BatchMode=yes -o ConnectTimeout=5"
if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'; else G= R= Y= B= N=; fi
PASS=0; FAILS=(); WARNS=()
pass() { echo "  ${G}PASS${N} $*"; PASS=$((PASS+1)); }
fail() { echo "  ${R}FAIL${N} $*"; FAILS+=("$*"); }
warn() { echo "  ${Y}WARN${N} $*"; WARNS+=("$*"); }
hdr()  { echo; echo "${B}== $* ==${N}"; }
fixing() { echo "  ${Y}FIX ${N} $*"; }

# ---------------------------------------------------------------- 0. reachability
hdr "0. Node reachability (ssh)"
UP_NODES=""
for h in $NODES; do
  if $SSH "$h" true 2>/dev/null; then pass "$h reachable"; UP_NODES="$UP_NODES $h"
  else fail "$h unreachable over ssh"; fi
done

# ---------------------------------------------------------------- 0b. clocks
# Runs before the SLURM checks: a skewed clock is the usual cause of down*.
node_skew() {   # $1=host -> |node time - login time| in seconds, empty if unreachable
  local t; t=$($SSH "$1" 'date +%s' 2>/dev/null) || return
  local s=$(( t - $(date +%s) )); echo "${s#-}"
}
GUARD_FILES="/etc/systemd/system/slurmd.service.d/wait-for-time.conf /etc/systemd/system/slurmd-resync.path"
install_guard() {   # $1=host; idempotent, takes effect from the next boot
  $SSH "$1" 'sudo bash -s' >/dev/null 2>&1 <<'EOF'
set -e
mkdir -p /etc/systemd/system/slurmd.service.d /etc/systemd/system/systemd-time-wait-sync.service.d
cat > /etc/systemd/system/slurmd.service.d/wait-for-time.conf <<'X'
# demo_check.sh --fix: don't start slurmd on the stale boot clock
[Unit]
Wants=time-sync.target
After=time-sync.target
X
cat > /etc/systemd/system/systemd-time-wait-sync.service.d/timeout.conf <<'X'
# demo_check.sh --fix: still boot (after 90s) when there is no network/NTP
[Service]
TimeoutStartSec=90
X
cat > /etc/systemd/system/slurmd-resync.path <<'X'
# demo_check.sh --fix: if NTP syncs late, restart slurmd once it does
[Unit]
Description=Restart slurmd once the clock is NTP-synchronized
[Path]
PathExists=/run/systemd/timesync/synchronized
[Install]
WantedBy=multi-user.target
X
cat > /etc/systemd/system/slurmd-resync.service <<'X'
[Unit]
Description=Restart slurmd after first NTP sync (stale boot clock breaks munge)
[Service]
Type=oneshot
ExecStart=/bin/systemctl try-restart slurmd.service
X
systemctl daemon-reload
systemctl enable systemd-time-wait-sync.service slurmd-resync.path
EOF
}

hdr "0b. Clocks (NTP sync + skew vs login)"
if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; then
  pass "login clock NTP-synchronized"
else
  warn "login clock not NTP-synchronized (no internet?) — nodes are synced to login's time instead"
fi
for h in $UP_NODES; do
  skew=$(node_skew "$h")
  [ -z "$skew" ] && { fail "$h clock unreadable"; continue; }
  if [ "$skew" -le $MAX_SKEW ]; then pass "$h clock skew ${skew}s"
  elif [ $FIX -eq 1 ]; then
    fixing "$h clock is ${skew}s off — forcing NTP resync"
    $SSH "$h" 'sudo systemctl restart systemd-timesyncd; for i in $(seq 20); do
      [ "$(timedatectl show -p NTPSynchronized --value)" = yes ] && break; sleep 1; done' 2>/dev/null
    skew=$(node_skew "$h")
    if [ "${skew:-999}" -gt $MAX_SKEW ]; then   # no NTP reachable: copy login's clock
      fixing "$h NTP did not converge — setting clock from login"
      $SSH "$h" "sudo date -s @$(date +%s)" >/dev/null 2>&1
      skew=$(node_skew "$h")
    fi
    if [ "${skew:-999}" -le $MAX_SKEW ]; then
      pass "$h clock skew ${skew}s after fix"
      fixing "$h restarting munge + slurmd on the corrected clock"
      $SSH "$h" "sudo systemctl restart munge slurmd" 2>/dev/null
    else fail "$h clock still ${skew}s off"; fi
  else
    fail "$h clock skew ${skew}s (>${MAX_SKEW}s) — munge will reject it; run --fix"
  fi
  # boot guard: stops this recurring after the next reboot
  if $SSH "$h" "ls $GUARD_FILES && systemctl is-enabled -q slurmd-resync.path" >/dev/null 2>&1; then
    pass "$h boot guard installed (slurmd waits for / restarts after NTP sync)"
  elif [ $FIX -eq 1 ]; then
    fixing "$h installing boot guard"
    install_guard "$h" && pass "$h boot guard installed" || fail "$h boot guard install failed"
  else
    warn "$h no boot guard — slurmd can start on a stale clock after reboot (run --fix)"
  fi
done

# ---------------------------------------------------------------- 1. sinfo
check_sinfo() {   # sets BAD; pass lines only when called with "report"
  BAD=""
  while read -r node state; do
    [ -z "$node" ] && continue
    if [ "$state" = "idle" ]; then [ "${1:-}" = report ] && pass "$node idle"
    else BAD="$BAD $node:$state"; fi
  done < <(sinfo -h -N -p cluster -o "%N %t" 2>/dev/null | sort -u)
}
hdr "1. Cluster is up (sinfo)"
if ! command -v sinfo >/dev/null; then
  fail "sinfo not found — run this on picluster-login"
else
  systemctl is-active --quiet slurmctld && pass "slurmctld active on login" \
    || fail "slurmctld not active on login"
  check_sinfo
  # with --fix and a bad node, idle nodes are reported once after the fix instead
  [ $FIX -eq 1 ] && [ -n "$BAD" ] || check_sinfo report
  if [ -n "$BAD" ] && [ $FIX -eq 1 ]; then
    for e in $BAD; do
      n=${e%%:*}; s=${e#*:}
      case "$s" in
        *'*'*)   # not responding -> slurmd/munge/clock problem (troubleshooting b–d)
          fixing "$n is $s (not responding) — restarting munge + slurmd"
          $SSH "$n" "sudo systemctl restart munge slurmd" 2>/dev/null ;;
      esac
    done
    # slurmd re-registers within a few seconds of a restart; poll rather than guess
    for ((i=0;i<30;i+=3)); do sleep 3; BAD=""; check_sinfo; [ -z "$BAD" ] && break; done
    # still down/drained (e.g. "Not responding" reason stuck) -> explicit resume
    for e in $BAD; do
      n=${e%%:*}; s=${e#*:}
      case "$s" in
        down*|drain*|drng*|fail*)
          fixing "$n is $s — scontrol resume"
          sudo scontrol update nodename="$n" state=resume 2>/dev/null ;;
      esac
    done
    sleep 3; BAD=""; check_sinfo report
  fi
  for e in $BAD; do
    n=${e%%:*}; s=${e#*:}
    hint=""
    $SSH "$n" "journalctl -b -u slurmd --no-pager | tail -50 | grep -qiE 'Rewound|out of sync'" 2>/dev/null \
      && hint=" — slurmd log shows clock skew; see section 0b"
    fail "$n state=$s  ($(sinfo -h -n "$n" -o '%E' -R 2>/dev/null | head -1))$hint"
  done
fi

# ---------------------------------------------------------------- troubleshooting checks
hdr "1b. Node services, hostname resolution, munge"
for h in $UP_NODES; do
  out=$($SSH "$h" 'echo "slurmd=$(systemctl is-active slurmd) munge=$(systemctl is-active munge) self=$(awk -v h=$(hostname) "!/^#/{for(i=2;i<=NF;i++) if(\$i==h) print \$1}" /etc/hosts | grep -m1 "^10\.0\.0\.")"' 2>/dev/null)
  sd=$(sed -n 's/.*slurmd=\([^ ]*\).*/\1/p' <<<"$out")
  mu=$(sed -n 's/.*munge=\([^ ]*\).*/\1/p' <<<"$out")
  ip=$(sed -n 's/.*self=\([^ ]*\).*/\1/p' <<<"$out")
  [ "$sd" = active ] && pass "$h slurmd active" || fail "$h slurmd=$sd  (journalctl -u slurmd -n 50)"
  [ "$mu" = active ] && pass "$h munge active"  || fail "$h munge=$mu"
  [[ "$ip" == 10.0.0.* ]] && pass "$h resolves itself -> $ip" \
    || fail "$h has no 10.0.0.x entry for itself — /etc/hosts missing cluster block"
done
first=$(echo $UP_NODES | awk '{print $1}')
if [ -n "$first" ]; then
  if $SSH "$first" "munge -n" 2>/dev/null | unmunge 2>/dev/null | grep -q 'STATUS:.*Success'; then
    pass "munge cross-auth $first -> login"
  else fail "munge credential from $first rejected on login (check munge.key)"; fi
fi

# ---------------------------------------------------------------- 2. NFS
hdr "2. Shared filesystem (/clusterfs)"
mountpoint -q /clusterfs && pass "login: /clusterfs present" || warn "login: /clusterfs is not a mountpoint (OK if it is the export dir)"
for h in $UP_NODES; do
  if $SSH "$h" "findmnt -n -t nfs,nfs4 /clusterfs" >/dev/null 2>&1; then
    pass "$h /clusterfs mounted (nfs)"
  elif [ $FIX -eq 1 ]; then
    fixing "$h mounting /clusterfs"
    $SSH "$h" "sudo mount -a" 2>/dev/null
    $SSH "$h" "findmnt -n -t nfs,nfs4 /clusterfs" >/dev/null 2>&1 \
      && pass "$h /clusterfs mounted after fix" || fail "$h /clusterfs still not mounted"
  else
    fail "$h /clusterfs not mounted  (ssh $h 'sudo mount -a')"
  fi
done
# write-visibility test: file written on login must be seen on a node
if [ -n "$first" ] && [ -w /clusterfs ]; then
  tok="/clusterfs/.democheck_$$"; echo ok > "$tok"
  $SSH "$first" "cat $tok" 2>/dev/null | grep -q ok \
    && pass "NFS write on login visible on $first" || fail "NFS write on login NOT visible on $first"
  rm -f "$tok"
fi

# ---------------------------------------------------------------- 3. files
hdr "3. Demo files in $PI_DIR"
if [ -d "$PI_DIR" ]; then
  ls "$PI_DIR"
  [ -f "$PI_DIR/pi_montecarlo.py" ] && pass "pi_montecarlo.py present" || fail "pi_montecarlo.py missing"
  JOB=""
  for f in pi-4rank-test.sh pi_4rank_test.sh pi-4rank.sh pi_4rank.sh; do
    [ -f "$PI_DIR/$f" ] && { JOB="$f"; break; }
  done
  [ -n "$JOB" ] && pass "test job script: $JOB" || fail "no 4-rank job script found"
  ls "$PI_DIR"/*1rank*.sh >/dev/null 2>&1 && pass "1-rank script present" || warn "no 1-rank script"
else
  fail "$PI_DIR does not exist"; JOB=""
fi

# ---------------------------------------------------------------- 4. SLURM smoke test
hdr "4. SLURM smoke test"
if command -v srun >/dev/null; then
  out=$(timeout 30 srun --chdir=/tmp -N1 -n4 hostname 2>&1)
  if [ $? -eq 0 ] && [ "$(wc -l <<<"$out")" -eq 4 ]; then
    pass "srun -N1 -n4 hostname -> $(sort -u <<<"$out" | tr '\n' ' ')"
  else fail "srun failed/timed out: $(head -1 <<<"$out")"; fi
  # all nodes at once
  out=$(timeout 30 srun --chdir=/tmp -N4 -n4 hostname 2>&1)
  [ $? -eq 0 ] && [ "$(sort -u <<<"$out" | wc -l)" -eq 4 ] \
    && pass "srun -N4 hits all 4 nodes" || fail "srun -N4 did not reach all nodes: $(head -1 <<<"$out")"

  if [ $QUICK -eq 0 ] && [ -n "$JOB" ]; then
    jid=$(cd "$PI_DIR" && sbatch --parsable "$JOB" 2>&1)
    if [[ "$jid" =~ ^[0-9]+ ]]; then
      jid=${jid%%;*}; echo "  submitted job $jid ($JOB), waiting up to ${SBATCH_TIMEOUT}s..."
      for ((i=0;i<SBATCH_TIMEOUT;i+=3)); do
        squeue -h -j "$jid" 2>/dev/null | grep -q . || break; sleep 3
      done
      st=$(sacct -n -X -j "$jid" -o State 2>/dev/null | awk 'NF{print $1; exit}')
      outf=$(ls -t "$PI_DIR"/*"$jid"*.out 2>/dev/null | head -1)
      if squeue -h -j "$jid" 2>/dev/null | grep -q .; then
        fail "job $jid still running after ${SBATCH_TIMEOUT}s"; scancel "$jid"
      elif [ -n "$outf" ] && grep -qi 'pi' "$outf" && ! grep -qiE 'error|traceback' "$outf"; then
        pass "job $jid completed${st:+ ($st)}: $(tail -1 "$outf")"
      else
        fail "job $jid ${st:-finished} — check output:"; [ -n "$outf" ] && tail -5 "$outf" | sed 's/^/        /'
      fi
    else fail "sbatch rejected: $jid"; fi
    rm -f "$PI_DIR"/*.out
    pass "cleaned $PI_DIR/*.out"
  fi
else
  fail "srun not found"
fi

# ---------------------------------------------------------------- 5. LEDs
hdr "5. LED matrix service (led-load)"
for h in $UP_NODES; do
  s=$($SSH "$h" "systemctl is-active led-load" 2>/dev/null)
  if [ "$s" = active ]; then pass "$h led-load active"
  elif [ $FIX -eq 1 ]; then
    fixing "$h restarting led-load"
    $SSH "$h" "sudo systemctl restart led-load" 2>/dev/null; sleep 2
    s=$($SSH "$h" "systemctl is-active led-load" 2>/dev/null)
    [ "$s" = active ] && pass "$h led-load active after restart" \
      || { fail "$h led-load=$s"; $SSH "$h" "journalctl -u led-load -n 5 --no-pager" 2>/dev/null | sed 's/^/        /'; }
  else fail "$h led-load=${s:-unknown}  (ssh $h 'sudo systemctl restart led-load')"; fi
done

# ---------------------------------------------------------------- summary
hdr "Summary"
echo "  ${G}${PASS} passed${N}, ${Y}${#WARNS[@]} warnings${N}, ${R}${#FAILS[@]} failed${N}"
for f in "${FAILS[@]}"; do echo "   - $f"; done
if [ ${#FAILS[@]} -eq 0 ]; then echo; echo "${G}${B}READY FOR DEMO${N}"; exit 0
else echo; echo "${R}${B}NOT READY${N}"; [ $FIX -eq 0 ] && echo "  Try: $0 --fix"; exit 1; fi
