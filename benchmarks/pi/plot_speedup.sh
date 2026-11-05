#!/bin/bash
# Prints a colored ASCII speedup chart from the pi_montecarlo.py .out files.
# Run from /clusterfs/pi after the jobs finish:
#   bash plot_speedup.sh
set -e
cd "$(dirname "$0")" 2>/dev/null || true
DIR=${1:-/clusterfs/pi}
cd "$DIR"

# Pulls all three numbers straight from the line:
#   "computed in <wall> s (<compute> s compute + <serial> s serial)"
# Prints "<wall> <compute> <serial>", or nothing if the file isn't there yet.
get_times () {
  # $1 = glob prefix, e.g. pi-1rank
  f=$(ls -t ${1}-*.out 2>/dev/null | head -n1)
  [ -z "$f" ] && return
  sed -nE 's/.*computed in ([0-9.]+) s \(([0-9.]+) s compute \+ ([0-9.]+) s serial\).*/\1 \2 \3/p' "$f"
}

read -r T1 C1 S1 <<< "$(get_times pi-1rank)"
read -r T4 C4 S4 <<< "$(get_times pi-4rank)"
read -r T16 C16 S16 <<< "$(get_times pi-16rank)"

[ -z "$T1" ] && { echo "No pi-1rank-*.out found in $DIR"; exit 1; }

RED='\033[0;31m'; BLUE='\033[1;36m'; BOLD='\033[1m'; RESET='\033[0m'
MAXWIDTH=50

bar () {
  local label=$1 wall=$2 compute=$3 serial=$4
  [ -z "$wall" ] && { printf "%-18s (no result yet)\n" "$label"; return; }
  local cwidth swidth
  cwidth=$(awk -v t="$compute" -v t1="$T1" -v w="$MAXWIDTH" 'BEGIN{n=int((t/t1)*w); print (n<1&&t>0)?1:n}')
  swidth=$(awk -v t="$serial"  -v t1="$T1" -v w="$MAXWIDTH" 'BEGIN{n=int((t/t1)*w); print (n<1&&t>0)?1:n}')
  printf "%-18s " "$label"
  printf "${RED}%${swidth}s${RESET}" '' | tr ' ' '#'
  printf "${BLUE}%${cwidth}s${RESET}" '' | tr ' ' '#'
  printf "  ${BOLD}%ss${RESET} ${RED}(%ss serial${RESET} + ${BLUE}%ss parallel)${RESET}\n" "$wall" "$serial" "$compute"
}

echo
echo -e "Wall time — ${RED}red = serial (fixed setup)${RESET}, ${BLUE}blue = parallel (splits across ranks)${RESET}:"
echo
bar "1 rank, 1 node"    "$T1"  "$C1"  "$S1"
bar "4 ranks, 1 node"   "$T4"  "$C4"  "$S4"
bar "16 ranks, 4 nodes" "$T16" "$C16" "$S16"
echo

if [ -n "$T4" ]; then
  SPEEDUP=$(awk -v a="$T1" -v b="$T4" 'BEGIN{printf "%.2f", a/b}')
  EFF=$(awk -v s="$SPEEDUP" 'BEGIN{printf "%.0f", (s/4)*100}')
  echo -e "${BOLD}Speedup (4 ranks vs 1): ${BLUE}${SPEEDUP}x${RESET}  (ideal: 4.00x, efficiency: ${EFF}%)"
fi
if [ -n "$T16" ]; then
  SPEEDUP16=$(awk -v a="$T1" -v b="$T16" 'BEGIN{printf "%.2f", a/b}')
  EFF16=$(awk -v s="$SPEEDUP16" 'BEGIN{printf "%.0f", (s/16)*100}')
  echo -e "${BOLD}Speedup (16 ranks vs 1): ${BLUE}${SPEEDUP16}x${RESET}  (ideal: 16.00x, efficiency: ${EFF16}%)"
fi
echo -e "${RED}Note: the red part is a fixed setup step every run pays in full — that's why speedup never reaches the ideal line.${RESET}"
echo
