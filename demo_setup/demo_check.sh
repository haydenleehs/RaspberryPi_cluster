#!/usr/bin/env bash
# picluster — automated pre-demo check (run on picluster-login)
# Mirrors demoCheck/README.md steps 1–5 plus the troubleshooting checks.
#
# Usage:  ./demo_check.sh            # check only
#         ./demo_check.sh --fix      # check + attempt the README's fixes
#         ./demo_check.sh --quick    # skip the sbatch job (step 4b)

set -u

NODES="${NODES:-picluster-node01 picluster-node02 picluster-node03 picluster-node04}"
PI_DIR="/clusterfs/pi"
SBATCH_TIMEOUT=120          # seconds to wait for the test job
FIX=0; QUICK=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    --quick) QUICK=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
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

# ---------------------------------------------------------------- 1. sinfo
check_sinfo() {
  BAD=""
  while read -r node state; do
    [ -z "$node" ] && continue
    if [ "$state" = "idle" ]; then pass "$node idle"
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
  if [ -n "$BAD" ] && [ $FIX -eq 1 ]; then
    for e in $BAD; do
      n=${e%%:*}; s=${e#*:}
      case "$s" in
        *'*'*)   # not responding -> slurmd/hosts problem (troubleshooting b–d)
          fixing "$n is $s (not responding) — restarting slurmd"
          $SSH "$n" "sudo systemctl restart slurmd" 2>/dev/null ;;
        down*|drain*|drng*)
          fixing "$n is $s — scontrol resume"
          sudo scontrol update nodename="$n" state=resume 2>/dev/null ;;
      esac
    done
    sleep 5; BAD=""; check_sinfo
  fi
  for e in $BAD; do
    n=${e%%:*}; s=${e#*:}
    fail "$n state=$s  ($(sinfo -h -n "$n" -o '%E' -R 2>/dev/null | head -1))"
  done
fi

# ---------------------------------------------------------------- troubleshooting checks
hdr "1b. Node services, hostname resolution, munge, clock"
LOGIN_T=$(date +%s)
for h in $UP_NODES; do
  out=$($SSH "$h" 'echo "slurmd=$(systemctl is-active slurmd) munge=$(systemctl is-active munge) self=$(awk -v h=$(hostname) "!/^#/{for(i=2;i<=NF;i++) if(\$i==h) print \$1}" /etc/hosts | grep -m1 "^10\.0\.0\.") t=$(date +%s)"' 2>/dev/null)
  sd=$(sed -n 's/.*slurmd=\([^ ]*\).*/\1/p' <<<"$out")
  mu=$(sed -n 's/.*munge=\([^ ]*\).*/\1/p' <<<"$out")
  ip=$(sed -n 's/.*self=\([^ ]*\).*/\1/p' <<<"$out")
  t=$(sed -n 's/.*t=\([0-9]*\).*/\1/p' <<<"$out")
  [ "$sd" = active ] && pass "$h slurmd active" || fail "$h slurmd=$sd  (journalctl -u slurmd -n 50)"
  [ "$mu" = active ] && pass "$h munge active"  || fail "$h munge=$mu"
  [[ "$ip" == 10.0.0.* ]] && pass "$h resolves itself -> $ip" \
    || fail "$h has no 10.0.0.x entry for itself — /etc/hosts missing cluster block"
  if [ -n "$t" ]; then
    skew=$(( t - LOGIN_T )); skew=${skew#-}
    [ "$skew" -le 5 ] && pass "$h clock skew ${skew}s" || warn "$h clock skew ${skew}s (>5s)"
  fi
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
  out=$(timeout 30 srun -N1 -n4 hostname 2>&1)
  if [ $? -eq 0 ] && [ "$(wc -l <<<"$out")" -eq 4 ]; then
    pass "srun -N1 -n4 hostname -> $(sort -u <<<"$out" | tr '\n' ' ')"
  else fail "srun failed/timed out: $(head -1 <<<"$out")"; fi
  # all nodes at once
  out=$(timeout 30 srun -N4 -n4 hostname 2>&1)
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
