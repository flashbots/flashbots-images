#!/usr/bin/env python3

import json
import csv
import requests
from pathlib import Path
from collections import defaultdict

def fetch_status(arch):
    """Fetch package reproducibility status from Debian CI."""
    url = f"https://{arch}.reproduce.debian.net/api/v0/pkgs/list"
    return {(p['name'], p['architecture']): p for p in requests.get(url).json()}

def main():
    # Load manifest
    with open("build/latest.manifest") as f:
        packages = [p for p in json.load(f)["packages"] if p["type"] == "deb"]
    
    # Fetch status from Debian CI
    print("Fetching reproducibility status from Debian CI...")
    amd64_status = fetch_status("amd64")
    all_status = fetch_status("all")
    status_data = {**amd64_status, **all_status}
    
    # Analyze packages
    results = []
    stats = defaultdict(int)
    
    for pkg in packages:
        name, version, arch = pkg["name"], pkg["version"], pkg["architecture"]
        
        # Look up status
        ci_pkg = status_data.get((name, arch))
        
        if not ci_pkg:
            status = "UNKNOWN"
            ci_version = "N/A"
        else:
            status = ci_pkg["status"]
            ci_version = ci_pkg["version"]
        
        version_match = version == ci_version
        
        results.append({
            "name": name,
            "architecture": arch,
            "version": version,
            "ci_version": ci_version,
            "status": status,
            "version_match": version_match
        })
        
        stats[status] += 1
        if not version_match and ci_pkg:
            stats["VERSION_MISMATCH"] += 1
    
    # Write CSV report
    with open("build/debian-ci-report.csv", 'w', newline='') as f:
        writer = csv.DictWriter(f, ["name", "architecture", "version", "ci_version", "status", "version_match"])
        writer.writeheader()
        writer.writerows(results)
    
    # Print summary
    total = len(results)
    print(f"\n{'='*50}")
    print(f"Total packages: {total}")
    for status, count in sorted(stats.items()):
        print(f"{status}: {count} ({count/total*100:.1f}%)")
    
    print(f"\nReport saved to: build/debian-ci-report.csv")

if __name__ == "__main__":
    main()