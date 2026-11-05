#!/bin/bash
out=$1
echo "time host temp_C scaling_MHz arm_clock_MHz throttled" > "$out"
while true; do
  t=$(awk '{printf "%.1f",$1/1000}' /sys/class/thermal/thermal_zone0/temp)
  s=$(awk '{printf "%d",$1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
  c=$(vcgencmd measure_clock arm 2>/dev/null | cut -d= -f2 | awk '{printf "%d",$1/1000000}')
  th=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
  echo "$(date +%T) $(hostname) $t $s ${c:-NA} ${th:-NA}" >> "$out"
  sleep 2
done
