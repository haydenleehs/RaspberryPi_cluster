#!/usr/bin/env python3
"""Web server on picluster-login that serves the HTML UI and triggers SLURM."""
import os
import json
import subprocess
from http.server import SimpleHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

os.chdir("/clusterfs/aero_turb")

class ClusterHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        
        # Endpoint 1: Trigger SLURM job from webpage button
        if parsed.path == "/submit":
            q = parse_qs(parsed.query)
            angle   = q.get("angle", ["6.0"])[0]
            camber  = q.get("camber", ["4.0"])[0]
            thick   = q.get("thick", ["12.0"])[0]
            turb    = q.get("turb", ["2.5"])[0]
            samples = q.get("samples", ["40000000"])[0]
            ranks   = int(q.get("ranks", ["16"])[0])
            nodes   = 1 if ranks <= 4 else 4
            label   = f"{ranks}-Cores"

            # Mark status as running
            with open("/clusterfs/aero_turb/mc_results.json", "w") as f:
                json.dump({"status": "running", "ranks": ranks, "nodes": nodes}, f)

            cmd = [
                "sbatch",
                f"--job-name=mc{ranks}",
                f"--nodes={nodes}",
                f"--ntasks={ranks}",
                "/clusterfs/aero_turb/turbulence.sh",
                angle, camber, thick, turb, samples, label
            ]
            out = subprocess.check_output(cmd).decode("utf-8").strip()
            self._send_json({"submitted": out, "ranks": ranks})
            return

        # Endpoint 2: Poll SLURM queue & results
        if parsed.path == "/status":
            squeue = subprocess.check_output(["squeue", "-h", "-o", "%i %j %T %M %N"]).decode("utf-8").strip()
            res = {"status": "idle"}
            if os.path.exists("/clusterfs/aero_turb/mc_results.json"):
                try:
                    with open("/clusterfs/aero_turb/mc_results.json") as f:
                        res = json.load(f)
                except Exception:
                    pass
            res["squeue"] = squeue
            self._send_json(res)
            return

        return super().do_GET()

    def _send_json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

if __name__ == "__main__":
    print("Serving Turbulence HPC Demo on http://10.0.0.1:8000/turbulence.html")
    HTTPServer(("0.0.0.0", 8000), ClusterHandler).serve_forever()
