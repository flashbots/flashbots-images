#!/usr/bin/env python3

import json
import subprocess
import csv
import hashlib
from pathlib import Path
import tempfile
import shutil

def sha256(filepath):
    """Calculate SHA256 hash of a file."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def get_source_package(binary_name):
    """Get source package name using apt-cache."""
    try:
        result = subprocess.run(
            ["apt-cache", "show", binary_name], 
            capture_output=True, 
            text=True
        )
        for line in result.stdout.split('\n'):
            if line.startswith('Source: '):
                source = line[8:].split(' ')[0].strip()
                return source
        return binary_name
    except:
        return binary_name

def verify_package(pkg, work_dir, cache_dir):
    """Verify a single package's reproducibility."""
    name, version, arch = pkg["name"], pkg["version"], pkg["architecture"]
    arch = "all" if arch == "all" else "amd64"
    
    # Get source package name
    source_name = get_source_package(name)
    
    # Strip epoch from version for buildinfo URL
    version_no_epoch = version.split(':', 1)[-1]
    
    # Download buildinfo using source package name
    folder = source_name[:4] if source_name.startswith("lib") else source_name[0]
    buildinfo = f"{source_name}_{version_no_epoch}_{arch}.buildinfo"
    url = f"https://buildinfos.debian.net/buildinfo-pool/{folder}/{source_name}/{buildinfo}"
    
    if subprocess.run(["wget", "-q", url], cwd=work_dir).returncode != 0:
        return "no-buildinfo"
    
    # Rebuild
    out_dir = work_dir / "out"
    out_dir.mkdir()
    
    if subprocess.run(["debrebuild", "--buildresult=out", "--builder=sbuild", buildinfo], 
                     cwd=work_dir, capture_output=True).returncode != 0:
        return "build-failed"
    
    # Look for the specific binary package we want
    rebuilt = list(out_dir.glob(f"{name}_{version_no_epoch}_{arch}.deb"))
    
    # For cached files, replace : with %3a
    version_encoded = version.replace(':', '%3a')
    cached = cache_dir / f"cache/apt/archives/{name}_{version_encoded}_{arch}.deb"
    
    if not rebuilt:
        return "no-output"
    if not cached.exists():
        return "no-cached"
    
    return "" if sha256(rebuilt[0]) == sha256(cached) else "mismatch"

def main():
    # Setup
    manifest = next(Path("/build").glob("*.manifest"))
    with open(manifest) as f:
        data = json.load(f)
    
    packages = [p for p in data["packages"] if p["type"] == "deb"]
    results = []
    
    # Process packages
    with tempfile.TemporaryDirectory() as tmpdir:
        for i, pkg in enumerate(packages, 1):
            print(f"[{i}/{len(packages)}] {pkg['name']} {pkg['version']}...", end=" ")
            
            work_dir = Path(tmpdir) / f"{pkg['name']}-{pkg['version']}"
            work_dir.mkdir()
            
            try:
                reason = verify_package(pkg, work_dir, Path("/mkosi.cache"))
                reproducible = not reason
                print("✓" if reproducible else f"✗ ({reason})")
            except Exception as e:
                reason = f"error: {e}"
                reproducible = False
                print(f"✗ ({reason})")
            
            results.append({
                "name": pkg["name"],
                "reproducible": reproducible,
                "reason": reason
            })
            
            shutil.rmtree(work_dir, ignore_errors=True)
    
    # Write report
    with open("/build/reproducible-report.csv", 'w', newline='') as f:
        writer = csv.DictWriter(f, ["name", "reproducible", "reason"])
        writer.writeheader()
        writer.writerows(results)
    
    # Summary
    total = len(results)
    repro = sum(r["reproducible"] for r in results)
    print(f"\nSummary: {repro}/{total} ({repro/total*100:.1f}%) reproducible")
    print("Report: /build/reproducible-report.csv")

if __name__ == "__main__":
    main()