#!/bin/bash
# Build the 25 GB Case-Sensitive Journaled HFS+ iOS 16.7.16 Root Image for Rosemary (Redmi Note 10S)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_DIR="/Volumes/files/rosemary/rootfs"
OS_DMG="$ROOTFS_DIR/087-86698-044.dmg"
SYSOS_DMG="$ROOTFS_DIR/087-86593-047.dmg"
APPOS_DMG="$ROOTFS_DIR/087-86715-047.dmg"
OUT_RAW="$ROOTFS_DIR/rosemary-ios16-root.raw"
OUT_SIMG="$ROOTFS_DIR/rosemary-ios16-root.simg"
SIZE="25G"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo $0) to preserve iOS file ownership and permissions." >&2
    exit 1
fi

echo "=========================================================="
echo " Building 25 GB iOS 16 Root Image for Rosemary (MT6785)"
echo "=========================================================="

for f in "$OS_DMG" "$SYSOS_DMG" "$APPOS_DMG"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: DMG not found: $f" >&2
        exit 1
    fi
done

MNT_ROOT="/tmp/rosemary_root_mnt"
MNT_OS="/tmp/rosemary_os_mnt"
MNT_SYSOS="/tmp/rosemary_sysos_mnt"
MNT_APPOS="/tmp/rosemary_appos_mnt"

mkdir -p "$MNT_ROOT" "$MNT_OS" "$MNT_SYSOS" "$MNT_APPOS"

DEV_RAW=""
DEV_OS=""
DEV_SYSOS=""
DEV_APPOS=""

cleanup() {
    echo "Cleaning up mounts and loop devices..."
    set +e
    umount "$MNT_ROOT" 2>/dev/null || true
    umount "$MNT_OS" 2>/dev/null || true
    umount "$MNT_SYSOS" 2>/dev/null || true
    umount "$MNT_APPOS" 2>/dev/null || true

    [[ -n "$DEV_OS" ]] && hdiutil detach "$DEV_OS" 2>/dev/null || true
    [[ -n "$DEV_SYSOS" ]] && hdiutil detach "$DEV_SYSOS" 2>/dev/null || true
    [[ -n "$DEV_APPOS" ]] && hdiutil detach "$DEV_APPOS" 2>/dev/null || true
    [[ -n "$DEV_RAW" ]] && hdiutil detach "$DEV_RAW" 2>/dev/null || true

    rmdir "$MNT_ROOT" "$MNT_OS" "$MNT_SYSOS" "$MNT_APPOS" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "1. Creating $SIZE sparse raw image at $OUT_RAW..."
rm -f "$OUT_RAW"
truncate -s "$SIZE" "$OUT_RAW"

echo "2. Attaching raw image..."
DEV_RAW=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$OUT_RAW" | head -n 1 | awk '{print $1}')
echo "   Raw device: $DEV_RAW"

echo "3. Formatting as Case-Sensitive Journaled HFS+ (iOSRoot)..."
newfs_hfs -s -J -v iOSRoot "$DEV_RAW"

echo "4. Mounting iOSRoot to $MNT_ROOT..."
mount -t hfs -o nobrowse "$DEV_RAW" "$MNT_ROOT"

echo "5. Attaching IPSW DMGs..."
DEV_OS=$(hdiutil attach -readonly -nobrowse -mountpoint "$MNT_OS" "$OS_DMG" | tail -n 1 | awk '{print $1}')
DEV_SYSOS=$(hdiutil attach -readonly -nobrowse -mountpoint "$MNT_SYSOS" "$SYSOS_DMG" | tail -n 1 | awk '{print $1}')
DEV_APPOS=$(hdiutil attach -readonly -nobrowse -mountpoint "$MNT_APPOS" "$APPOS_DMG" | tail -n 1 | awk '{print $1}')

echo "   OS mounted at $MNT_OS"
echo "   SystemOS mounted at $MNT_SYSOS"
echo "   AppOS mounted at $MNT_APPOS"

echo "6. Copying OS root filesystem..."
rsync -aH --numeric-ids "$MNT_OS/" "$MNT_ROOT/"

echo "7. Copying Cryptexes..."
mkdir -p "$MNT_ROOT/private/preboot/Cryptexes/OS" "$MNT_ROOT/private/preboot/Cryptexes/App"
rsync -aH --numeric-ids "$MNT_SYSOS/" "$MNT_ROOT/private/preboot/Cryptexes/OS/"
rsync -aH --numeric-ids "$MNT_APPOS/" "$MNT_ROOT/private/preboot/Cryptexes/App/"

echo "8. Linking shared cache to ignition level 1 path..."
mkdir -p "$MNT_ROOT/System/Library/Caches/com.apple.dyld"
DSC="private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld"
for f in "$MNT_ROOT/$DSC"/*; do
    if [[ -f "$f" ]]; then
        ln -f "$f" "$MNT_ROOT/System/Library/Caches/com.apple.dyld/${f##*/}"
    fi
done

echo "9. Hardlinking cryptex files without counterpart into root..."
for c in OS App; do
    (cd "$MNT_ROOT/private/preboot/Cryptexes/$c" && find . ! -type d ! -path './System/Library/Caches/com.apple.dyld/*') |
    while IFS= read -r f; do
        f=${f#./}
        if [[ ! -e "$MNT_ROOT/$f" && ! -L "$MNT_ROOT/$f" ]]; then
            mkdir -p "$MNT_ROOT/$(dirname "$f")"
            src="$MNT_ROOT/private/preboot/Cryptexes/$c/$f"
            if [[ -L "$src" ]]; then
                cp -P "$src" "$MNT_ROOT/$f"
            else
                ln "$src" "$MNT_ROOT/$f"
            fi
        fi
    done
done

echo "10. Setting up diagnostics & log directories..."
DB="$MNT_ROOT/private/var/db"
install -d -o 272 -g 272 -m 0751 "$DB/diagnostics"
install -d -o 272 -g 272 -m 0755 "$DB/uuidtext" "$DB/diagnostics/timesync"
for d in diagnostics uuidtext diagnostics/timesync; do
    install -o 272 -g 272 -m 0644 /dev/null "$DB/$d/.migrated"
done

echo "11. Creating plain system keybag for AppleKeyStore..."
install -d -m 0700 -o 0 -g 0 "$MNT_ROOT/private/var/keybags"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' |
    install -m 0600 -o 0 -g 0 /dev/stdin "$MNT_ROOT/private/var/keybags/systembag.kb"

echo "12. Applying SWEET system tweaks (launchd, containers, activation, watchdog)..."
python3 "$SCRIPT_DIR/sweet-root-tweaks.py" "$MNT_ROOT"

echo "13. Syncing and verifying HFS+ filesystem..."
sync
df -h "$MNT_ROOT"

echo "Unmounting cleanly..."
umount "$MNT_ROOT"
fsck_hfs -f "$DEV_RAW" || true

echo "Detaching devices..."
hdiutil detach "$DEV_OS"
hdiutil detach "$DEV_SYSOS"
hdiutil detach "$DEV_APPOS"
hdiutil detach "$DEV_RAW"
DEV_OS="" DEV_SYSOS="" DEV_APPOS="" DEV_RAW=""

echo "14. Converting raw image to Android sparse image (.simg)..."
python3 "$SCRIPT_DIR/img2simg.py" "$OUT_RAW" "$OUT_SIMG"

echo "=========================================================="
echo " Successfully built: $OUT_SIMG"
ls -lh "$OUT_SIMG"
echo "=========================================================="
