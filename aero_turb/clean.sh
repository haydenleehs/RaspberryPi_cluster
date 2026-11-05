#!/bin/bash
# Remove Slurm output files (mc-*.out) and the results JSON from previous runs.
cd /clusterfs/aero_turb || exit 1

shopt -s nullglob
files=(mc-*.out mc_results.json)

if [ ${#files[@]} -eq 0 ]; then
    echo "Nothing to clean."
    exit 0
fi

rm -f -- "${files[@]}"
printf 'Removed: %s\n' "${files[@]}"
