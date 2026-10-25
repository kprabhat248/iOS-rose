#!/usr/bin/env python3
"""Build a 25 GB case-sensitive journaled HFS+ iOS 16 root image for Rosemary on macOS."""
import os
import shutil
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOTFS_DIR = "/Volumes/files/rosemary/rootfs"
OS_DMG = os.path.join(ROOTFS_DIR, "087-86698-044.dmg")
SYSOS_DMG = os.path.join(ROOTFS_DIR, "087-86593-047.dmg")
APPOS_DMG = os.path.join(ROOTFS_DIR, "087-86715-047.dmg")
OUT_RAW = os.path.join(ROOTFS_DIR, "rosemary-ios16-root.raw")
OUT_SIMG = os.path.join(ROOTFS_DIR, "rosemary-ios16-root.simg")
SIZE_GB = 25
MNT_ROOT = "/tmp/rosemary_iosroot"


def run(cmd, check=True, capture=False):
    print(f"-> {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    if capture:
        return subprocess.check_output(cmd, text=True)
    return subprocess.run(cmd, check=check)


def attach_dmg(dmg_path):
    out = run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noverify", dmg_path], capture=True)
    lines = out.strip().split("\n")
    base_dev = lines[0].split("\t")[0].strip()
    mnt_point = None
    for line in lines:
        parts = line.split("\t")
        if len(parts) >= 3 and parts[-1].strip().startswith("/Volumes/"):
            mnt_point = parts[-1].strip()
    if not mnt_point:
        raise RuntimeError(f"Failed to find mount point in hdiutil output for {dmg_path}:\n{out}")
    print(f"   Attached {os.path.basename(dmg_path)}: base={base_dev}, mount={mnt_point}")
    return base_dev, mnt_point


def detach_dev(dev):
    if dev:
        try:
            run(["hdiutil", "detach", dev], check=False)
        except Exception as e:
            print(f"Warning detaching {dev}: {e}")


def main():
    if os.geteuid() != 0:
        print("Error: this script must be run as root (sudo ./tools/build_rosemary_root.py)")
        sys.exit(1)

    for f in (OS_DMG, SYSOS_DMG, APPOS_DMG):
        if not os.path.isfile(f):
            print(f"Error: required DMG not found: {f}")
            sys.exit(1)

    os.makedirs(MNT_ROOT, exist_ok=True)

    raw_dev = None
    os_dev, sysos_dev, appos_dev = None, None, None

    try:
        print(f"1. Creating {SIZE_GB} GB sparse raw image at {OUT_RAW}...")
        if os.path.exists(OUT_RAW):
            os.remove(OUT_RAW)
        with open(OUT_RAW, "wb") as f:
            f.truncate(SIZE_GB * 1024 * 1024 * 1024)

        print("2. Attaching raw image...")
        out = run(["hdiutil", "attach", "-imagekey", "diskimage-class=CRawDiskImage", "-nomount", OUT_RAW], capture=True)
        raw_dev = out.strip().split("\n")[0].split("\t")[0].strip()
        print(f"   Raw loop device: {raw_dev}")

        print("3. Formatting as Case-Sensitive Journaled HFS+ (iOSRoot)...")
        run(["newfs_hfs", "-s", "-J", "-v", "iOSRoot", raw_dev])

        print(f"4. Mounting iOSRoot to {MNT_ROOT}...")
        run(["mount", "-t", "hfs", "-o", "nobrowse", raw_dev, MNT_ROOT])

        print("5. Attaching IPSW DMGs...")
        os_dev, os_mnt = attach_dmg(OS_DMG)
        sysos_dev, sysos_mnt = attach_dmg(SYSOS_DMG)
        appos_dev, appos_mnt = attach_dmg(APPOS_DMG)

        print(f"6. Copying OS root filesystem from {os_mnt}...")
        run(["rsync", "-aH", "--numeric-ids", f"{os_mnt}/", f"{MNT_ROOT}/"])

        print(f"7. Copying Cryptexes from {sysos_mnt} and {appos_mnt}...")
        cryptex_os = os.path.join(MNT_ROOT, "private/preboot/Cryptexes/OS")
        cryptex_app = os.path.join(MNT_ROOT, "private/preboot/Cryptexes/App")
        os.makedirs(cryptex_os, exist_ok=True)
        os.makedirs(cryptex_app, exist_ok=True)
        run(["rsync", "-aH", "--numeric-ids", f"{sysos_mnt}/", f"{cryptex_os}/"])
        run(["rsync", "-aH", "--numeric-ids", f"{appos_mnt}/", f"{cryptex_app}/"])

        print("8. Linking dyld shared cache to ignition level 1 path...")
        cache_dest = os.path.join(MNT_ROOT, "System/Library/Caches/com.apple.dyld")
        os.makedirs(cache_dest, exist_ok=True)
        cache_src = os.path.join(cryptex_os, "System/Library/Caches/com.apple.dyld")
        if os.path.isdir(cache_src):
            for fname in os.listdir(cache_src):
                s = os.path.join(cache_src, fname)
                d = os.path.join(cache_dest, fname)
                if os.path.isfile(s) and not os.path.exists(d):
                    os.link(s, d)

        print("9. Linking cryptex files without counterpart into root...")
        for cname, cdir in [("OS", cryptex_os), ("App", cryptex_app)]:
            for root, dirs, files in os.walk(cdir):
                rel = os.path.relpath(root, cdir)
                if rel.startswith("System/Library/Caches/com.apple.dyld"):
                    continue
                for f in files:
                    src_f = os.path.join(root, f)
                    rel_f = os.path.relpath(src_f, cdir)
                    dest_f = os.path.join(MNT_ROOT, rel_f)
                    if not os.path.exists(dest_f) and not os.path.islink(dest_f):
                        os.makedirs(os.path.dirname(dest_f), exist_ok=True)
                        if os.path.islink(src_f):
                            target = os.readlink(src_f)
                            os.symlink(target, dest_f)
                        else:
                            try:
                                os.link(src_f, dest_f)
                            except OSError:
                                shutil.copy2(src_f, dest_f)

        print("10. Setting up diagnostics and system keybag...")
        db = os.path.join(MNT_ROOT, "private/var/db")
        for sub, mode in [("diagnostics", 0o751), ("uuidtext", 0o755), ("diagnostics/timesync", 0o755)]:
            p = os.path.join(db, sub)
            os.makedirs(p, exist_ok=True)
            os.chown(p, 272, 272)
            os.chmod(p, mode)
            marker = os.path.join(p, ".migrated")
            with open(marker, "wb") as mf:
                pass
            os.chown(marker, 272, 272)
            os.chmod(marker, 0o644)

        keybag_dir = os.path.join(MNT_ROOT, "private/var/keybags")
        os.makedirs(keybag_dir, exist_ok=True)
        os.chown(keybag_dir, 0, 0)
        os.chmod(keybag_dir, 0o700)
        kb_path = os.path.join(keybag_dir, "systembag.kb")
        kb_content = (
            b'<?xml version="1.0" encoding="UTF-8"?>\n'
            b'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            b'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>\n'
        )
        with open(kb_path, "wb") as kf:
            kf.write(kb_content)
        os.chown(kb_path, 0, 0)
        os.chmod(kb_path, 0o600)

        print("11. Applying SWEET system tweaks...")
        run([sys.executable, os.path.join(SCRIPT_DIR, "sweet-root-tweaks.py"), MNT_ROOT])

        print("12. Syncing filesystem...")
        run(["sync"])
        run(["df", "-h", MNT_ROOT])

    finally:
        print("Cleaning up mounts...")
        try:
            run(["umount", MNT_ROOT], check=False)
        except Exception:
            pass
        detach_dev(os_dev)
        detach_dev(sysos_dev)
        detach_dev(appos_dev)
        detach_dev(raw_dev)

    print("13. Converting raw image to Android sparse image (.simg)...")
    run([sys.executable, os.path.join(SCRIPT_DIR, "img2simg.py"), OUT_RAW, OUT_SIMG])

    print("==========================================================")
    print(f" SUCCESS: 25 GB iOS 16 Root Image built: {OUT_SIMG}")
    print("==========================================================")


if __name__ == "__main__":
    main()
