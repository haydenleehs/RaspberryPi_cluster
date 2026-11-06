#!/usr/bin/env python3
"""Summarise HPL runs with the temperature / clock / throttle logs from templog.sh.

For each HPL output file (hpl-<N>node-<jobid>.out) it finds the matching
monitor_<host>_<jobid>.log files in the same folder and reports, per node,
during the HPL solve (between HPL's start and end time):
  - temperature before the run, peak, and average
  - ARM clock: average and lowest
  - throttle flags seen (vcgencmd get_throttled), decoded

Usage:
    python3 hpl_thermal_summary.py                        # all runs in /clusterfs/hpl/hpl_*node
    python3 hpl_thermal_summary.py hpl_4node/hpl-4node-57.out ...   # specific runs
"""
import glob
import os
import re
import sys
from datetime import datetime

THROTTLE_BITS = {
    0: "under-voltage NOW",
    1: "ARM frequency capped NOW",
    2: "throttled NOW",
    3: "soft temperature limit NOW",
    16: "under-voltage has occurred",
    17: "ARM frequency capping has occurred",
    18: "throttling has occurred",
    19: "soft temperature limit has occurred",
}


def decode_throttle(value):
    try:
        v = int(value, 16)
    except ValueError:
        return [f"unreadable ({value})"]
    return [msg for bit, msg in THROTTLE_BITS.items() if v & (1 << bit)]


def secs(hms):
    h, m, s = map(int, hms.split(":"))
    return h * 3600 + m * 60 + s


def parse_out(path):
    text = open(path).read()
    res = {"path": path}
    m = re.search(r"^(W\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.eE+-]+)",
                  text, re.M)
    if m:
        res.update(N=int(m[2]), NB=int(m[3]), P=int(m[4]), Q=int(m[5]),
                   time=float(m[6]), gflops=float(m[7]))
    res["passed"] = "PASSED" in text
    for key in ("start", "end"):
        t = re.search(rf"HPL_pdgesv\(\) {key} time\s+(.+)", text)
        if t:
            res[key] = datetime.strptime(t[1].strip(), "%a %b %d %H:%M:%S %Y").strftime("%H:%M:%S")
    m = re.search(r"nodes=(\S+) ranks=(\d+)", text)
    if m:
        res["nodelist"], res["ranks"] = m[1], int(m[2])
    return res


def read_log(path):
    rows = []
    for line in open(path).read().splitlines()[1:]:
        p = line.split()
        if len(p) < 6:
            continue
        try:
            rows.append({"t": secs(p[0]), "host": p[1], "temp": float(p[2]),
                         "clk": int(p[4]) if p[4] != "NA" else int(p[3]), "thr": p[5]})
        except ValueError:
            continue
    return rows


def summarise(out_path):
    run = parse_out(out_path)
    jobid = re.search(r"-(\d+)\.out$", out_path)
    jobid = jobid[1] if jobid else "?"
    print("=" * 78)
    print(f"{os.path.basename(out_path)}   job {jobid}   {run.get('nodelist', '?')}   "
          f"{run.get('ranks', '?')} ranks")
    if "gflops" not in run:
        print("  no HPL result line found (job unfinished or failed)")
        return
    print(f"  N={run['N']}  NB={run['NB']}  P×Q={run['P']}×{run['Q']}  "
          f"time={run['time']:.1f} s  -> {run['gflops']:.2f} GFLOPS  "
          f"[{'PASSED' if run['passed'] else 'NOT PASSED'}]")
    logs = sorted(glob.glob(os.path.join(os.path.dirname(out_path) or ".",
                                         f"monitor_*_{jobid}.log")))
    if not logs:
        print("  no monitor logs for this job (it ran without templog.sh)")
        return
    if "start" not in run or "end" not in run:
        print("  HPL start/end time missing; using the whole log")
    t0 = secs(run["start"]) if "start" in run else None
    t1 = secs(run["end"]) if "end" in run else None
    print(f"  solve window: {run.get('start', '?')} -> {run.get('end', '?')}")
    print(f"  {'node':<18}{'before':>8}{'peak':>8}{'avg':>8}{'avg clk':>10}{'min clk':>10}  throttle")
    any_throttle = False
    for log in logs:
        rows = read_log(log)
        if not rows:
            continue
        host = rows[0]["host"]
        during = [r for r in rows if t0 is None or (t0 <= r["t"] <= t1)] or rows
        before = [r for r in rows if t0 is not None and r["t"] < t0] or rows[:1]
        flags = sorted({r["thr"] for r in rows})
        bad = [f for f in flags if f not in ("0x0", "NA")]
        any_throttle |= bool(bad)
        thr = "none (0x0)" if not bad else "; ".join(
            f"{f}: {', '.join(decode_throttle(f))}" for f in bad)
        avg_t = sum(r["temp"] for r in during) / len(during)
        avg_c = sum(r["clk"] for r in during) / len(during)
        print(f"  {host:<18}{before[0]['temp']:>7.1f}C{max(r['temp'] for r in during):>7.1f}C"
              f"{avg_t:>7.1f}C{avg_c:>7.0f} MHz{min(r['clk'] for r in during):>6} MHz  {thr}")
    print("  verdict:", "THROTTLING DETECTED, results may be lower than the hardware can do"
          if any_throttle else "no throttling: CPUs ran at full speed")


def main():
    outs = sys.argv[1:] or sorted(glob.glob("/clusterfs/hpl/hpl_*node/hpl-*node-*.out"),
                                  key=lambda p: (p.split("/")[-2], int(re.search(r"-(\d+)\.out$", p)[1])))
    if not outs:
        sys.exit("no HPL output files found")
    for o in outs:
        summarise(o)


if __name__ == "__main__":
    main()
