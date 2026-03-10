#!/usr/bin/env python3
"""
copy_drivers.py - Extract Xbox/GIP kernel drivers from Windows system32.

Copies the three kernel drivers used by the GameSir G7 SE (and other
Xbox/GIP controllers) out of system32\\DRIVERS for offline analysis:

  dc1-controller.sys  — Device-specific controller minidriver
  devauthe.sys         — GIP device authentication
  xboxgip.sys          — Core GIP transport

No external dependencies — uses only stdlib.

The --decompile flag works on any platform where Ghidra is installed (Windows,
macOS, Linux). The copy step requires Windows (or pre-copied .sys files).

Usage:
  python copy_drivers.py                  # Copy drivers to ./drivers/ (Windows)
  python copy_drivers.py --decompile      # Copy + decompile via Ghidra headless
  python copy_drivers.py --decompile-only # Decompile existing files in ./drivers/
"""

import sys
import os
import shutil
import hashlib
import subprocess

DRIVERS = [
    "dc1-controller.sys",
    "devauthe.sys",
    "xboxgip.sys",
]

GHIDRA_SCRIPT = "decompile_driver.ghidra.py"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_drivers(out_dir):
    windir = os.environ.get("windir", r"C:\Windows")
    src_dir = os.path.join(windir, "System32", "DRIVERS")

    os.makedirs(out_dir, exist_ok=True)
    print(f"[INFO] Source: {src_dir}")
    print(f"[INFO] Output: {os.path.abspath(out_dir)}")
    print()

    copied = []
    for name in DRIVERS:
        src = os.path.join(src_dir, name)
        dst = os.path.join(out_dir, name)

        if not os.path.isfile(src):
            print(f"[ERROR] Not found: {src}")
            continue

        shutil.copy2(src, dst)
        size = os.path.getsize(dst)
        digest = sha256_file(dst)
        print(f"[INFO] {name}")
        print(f"       Size:   {size:,} bytes")
        print(f"       SHA256: {digest}")
        print()
        copied.append(dst)

    return copied


def decompile(out_dir, driver_paths):
    ghidra_install = os.environ.get("GHIDRA_INSTALL_DIR", "")
    if not ghidra_install:
        print("[ERROR] GHIDRA_INSTALL_DIR not set. Set it to your Ghidra installation root.")
        if sys.platform == "win32":
            print("        Example: set GHIDRA_INSTALL_DIR=C:\\ghidra_11.0")
        else:
            print("        Example: export GHIDRA_INSTALL_DIR=/opt/ghidra_11.0")
        sys.exit(1)

    headless = os.path.join(ghidra_install, "support", "analyzeHeadless.bat")
    if not os.path.isfile(headless):
        headless = os.path.join(ghidra_install, "support", "analyzeHeadless")
        if not os.path.isfile(headless):
            print(f"[ERROR] analyzeHeadless not found in {ghidra_install}/support/")
            sys.exit(1)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    script_path = os.path.join(script_dir, GHIDRA_SCRIPT)
    if not os.path.isfile(script_path):
        print(f"[ERROR] Ghidra script not found: {script_path}")
        sys.exit(1)

    project_dir = os.path.join(out_dir, ".ghidra_tmp")
    os.makedirs(project_dir, exist_ok=True)

    for path in driver_paths:
        name = os.path.splitext(os.path.basename(path))[0]
        print(f"[INFO] Decompiling {os.path.basename(path)} ...")

        cmd = [
            headless,
            project_dir,
            f"proj_{name}",
            "-import", os.path.abspath(path),
            "-postScript", script_path, os.path.abspath(out_dir),
            "-deleteProject",
            "-analysisTimeoutPerFile", "600",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"[ERROR] Ghidra failed for {os.path.basename(path)}")
            print(result.stderr[-2000:] if len(result.stderr) > 2000 else result.stderr)
        else:
            c_file = os.path.join(out_dir, f"{name}_decompiled.c")
            txt_file = os.path.join(out_dir, f"{name}_functions.txt")
            if os.path.isfile(c_file):
                print(f"[INFO] Pseudocode: {c_file}")
            if os.path.isfile(txt_file):
                print(f"[INFO] Functions:  {txt_file}")
        print()

    # Clean up temp project dir if empty
    try:
        os.rmdir(project_dir)
    except OSError:
        pass


def find_existing_drivers(out_dir):
    """Find .sys files already present in the output directory."""
    found = []
    for name in DRIVERS:
        path = os.path.join(out_dir, name)
        if os.path.isfile(path):
            found.append(path)
    return found


def main():
    flags = set(sys.argv[1:])
    do_decompile = "--decompile" in flags
    decompile_only = "--decompile-only" in flags

    out_dir = os.path.join(".", "drivers")

    if decompile_only:
        targets = find_existing_drivers(out_dir)
        if not targets:
            print(f"[ERROR] No .sys files found in {os.path.abspath(out_dir)}")
            print("        Copy driver files there first, or run without --decompile-only on Windows.")
            sys.exit(1)
        print(f"[INFO] Found {len(targets)} driver(s) in {os.path.abspath(out_dir)}")
        for path in targets:
            digest = sha256_file(path)
            print(f"[INFO] {os.path.basename(path)}  SHA256: {digest}")
        print()
        decompile(out_dir, targets)
        return

    copied = copy_drivers(out_dir)

    if not copied:
        print("[ERROR] No drivers were copied.")
        sys.exit(1)

    print(f"[INFO] Copied {len(copied)}/{len(DRIVERS)} driver(s).")

    if do_decompile:
        print()
        decompile(out_dir, copied)


if __name__ == "__main__":
    main()
