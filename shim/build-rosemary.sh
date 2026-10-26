#!/bin/bash
# Build the rosemary (Redmi Note 10S / MT6785) shim and wrap it in a boot.img v2
# identical in layout to the MTK LK images that LK accepts:
# gzipped kernel, stock ramdisk, MTK DTB table, pagesize 2048.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

DEFAULT_DTB="/Volumes/files/rosemary/boot_unpacked/dtb"

DEFAULT_RAMDISK="/Volumes/files/rosemary/boot_unpacked/ramdisk"
RAMDISK=${RAMDISK:-$DEFAULT_RAMDISK}
if [ $# -ge 1 ]; then
	RAMDISK=$1
fi


DTB=${DTB:-$DEFAULT_DTB}
if [ ! -f "$DTB" ]; then
	if [ -f "$ROOT_DIR/research/rosemary_stock_dtb.bin" ]; then
		DTB="$ROOT_DIR/research/rosemary_stock_dtb.bin"
	else
		DTB="$MUSI/Resources/DTBs/rosemary_stock_dtbtable.bin"
	fi
fi

MKBOOTIMG=${MKBOOTIMG:-$ROOT_DIR/tools/mkbootimg.py}


CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -fno-jump-tables -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra -DFB_STRIDE=4352"

if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
	CC="aarch64-linux-gnu-gcc"
	OBJCOPY="aarch64-linux-gnu-objcopy"
	READELF="aarch64-linux-gnu-readelf"
	NM="aarch64-linux-gnu-nm"
	LINK_CMD="$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N"
else
	CLANG="/opt/homebrew/opt/llvm/bin/clang"
	if [ ! -x "$CLANG" ]; then
		CLANG="clang"
	fi
	CC="$CLANG --target=aarch64-none-elf"
	OBJCOPY=$(command -v llvm-objcopy || echo "/opt/homebrew/opt/llvm/bin/llvm-objcopy")
	READELF=$(command -v llvm-readelf || echo "/opt/homebrew/opt/llvm/bin/llvm-readelf")
	NM=$(command -v llvm-nm || echo "/opt/homebrew/opt/llvm/bin/llvm-nm")
	LLD=$(command -v ld.lld || echo "/opt/homebrew/bin/ld.lld")
	LINK_CMD="$LLD -static -T shim.ld --build-id=none -N"
fi

mkdir -p out
for f in start.S shim.c console.c mmu.c fdt.c loader.c ufs.c; do
	$CC $CFLAGS -c $f -o out/${f%.*}.o
done

# The image runs wherever LK puts it with no relocation pass: only the
# header's image_size (start.o, linked at 0) may be an absolute address.
abs=$($READELF -r out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }

$LINK_CMD out/start.o out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o -o out/shim.elf
$OBJCOPY -O binary out/shim.elf out/Image

# LK copies the decompressed file; pad to image_size so .bss/stacks exist.
size=$($NM out/shim.elf | python3 -c "import sys; lines=[l.split() for l in sys.stdin if len(l.split())>=3 and l.split()[2]=='_end']; print(int(lines[0][0], 16))")
truncate -s "$size" out/Image



# Stock-style gzip stream (no FNAME/mtime, XFL=2, OS=3)
python3 - "$PWD/out/Image" "$PWD/out/Image.gz" <<'PY'
import sys, zlib
src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
c = zlib.compressobj(9, zlib.DEFLATED, -zlib.MAX_WBITS)
body = c.compress(data) + c.flush()
gz = (b'\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\x03' + body +
      zlib.crc32(data).to_bytes(4, 'little') + len(data).to_bytes(4, 'little'))
open(dst, 'wb').write(gz)
print(f'shim: {len(data)} bytes -> gzip {len(gz)} bytes')
PY

python3 "$MKBOOTIMG" --kernel out/Image.gz --ramdisk "$RAMDISK" --dtb "$DTB" \
	--base 0x40078000 --kernel_offset 0x8000 --ramdisk_offset 0x07C08000 \
	--tags_offset 0x0BC08000 --dtb_offset 0x0BC08000 --pagesize 2048 \
	--header_version 2 --os_version 12.0 \
	--cmdline "bootopt=64S3,32N2,64N2 buildvariant=user" \
	-o out/shim-rosemary.img
ls -l out/Image out/Image.gz out/shim-rosemary.img
