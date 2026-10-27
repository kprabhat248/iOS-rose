# iOS 16 on rosemary (Redmi Note 10S, MT6785) - working notes

## Goal
Port Apple's XNU kernel (iOS 16 generation) and the iOS 16.7.16 userland stack to the Redmi Note 10S "rosemary" (MediaTek Helio G95 / MT6785), building upon the work from `sweet` and `fleur`.

## Branch Information
- **Branch**: `rosemary` (branched from `fleur` at commit `9c40e1a`)
- **Remote**: `origin/rosemary` (tracked)

---

## Hardware Overview & Verified Facts (from Stock DTB & DTBO Extraction)

| Component | Verified Specification on Rosemary (MT6785) | Details & Offsets |
|-----------|---------------------------------------------|-------------------|
| **SoC** | MediaTek Helio G95 (MT6785) | MTK 64-bit ARMv8.2-A |
| **CPU Cluster** | 8 Cores: 6× Cortex-A55 + 2× Cortex-A75 | MPIDR: 0x000, 0x100, 0x200, 0x300, 0x400, 0x500 (A55), 0x600, 0x700 (A75) |
| **RAM** | 6 GB / 8 GB LPDDR4X | Base `0x40000000`, size `0x3E605000` (LK patches to full RAM) |
| **Display** | 1080×2400 AMOLED (60Hz) | LK mblock FB carve-out |
| **GICv3** | GICD `0x0C000000` (size `0x40000`), GICR `0x0C040000` (size `0x200000`) | GICv3 matching MT6781 |
| **Timer** | 13 MHz (`0xC65D40`) | PPIs 13/14/11/10 → INTIDs 29/30/27/26 (VTIMER = 27, PTIMER = 30) |
| **PSCI** | PSCI 1.0, `method = "smc"` | SYSTEM_RESET + CPU_ON supported |
| **Storage** | UFS 2.2 at `0x11270000` (size `0x2300`) | MTK UFSHCI |
| **Touch** | Goodix GT9885 (`0x5d`) / FocalTech FTS (`0x38`) on I2C 0 (`0x11007000`) | Reset GPIO 2, IRQ GPIO 1 (on pio) |
| **Buttons** | MTK Keypad at `0x10010000` (IRQ 75) + PMIC Power Key | Power, Vol+ / Vol- |
| **Boot Header** | Android boot v2 | `kernel_addr: 0x40080000`, `ramdisk_addr: 0x47C80000`, `tags_addr: 0x4BC80000`, `page_size: 2048` |

---

## Step-by-Step Bring-up Roadmap for Rosemary

### Step 1: Device Inspection & Backup
1. **Stock Partition Backup & Extraction** (Completed):
   - Fastboot ROM (`V14.0.11.0.TKLINXM`) downloaded to `/Volumes/files/rosemary/rosemary_in_fastboot.tgz`.
   - Extracted `boot.img`, `dtbo.img`, `vbmeta.img`.
   - Unpacked `boot.img` with `tools/unpack_bootv2.py`.
   - Decompiled DTB to `rosemary.dts` and DTBO overlay to `rosemary_dtbo.dts`.
   - All hardware addresses, CPU clusters, and I2C touch pins verified.


### Step 2: Shim & Early Framebuffer Console
1. Create `shim/build-rosemary.sh` using rosemary's stock DTB and kernel base offsets.
2. Verify LK entry point: CurrentEL (EL1 / EL2), MMU status, and MTK WDT disable (toprgu).
3. Validate framebuffer address (`FB_BASE`, `FB_STRIDE`) and display diagnostic banner on screen.
4. Bring up secondary CPU cores via PSCI SMC calls (`PSCI_CPU_ON`).

### Step 3: Apple Device Tree (ADT) for Rosemary
1. Extend `tools/mkadt.py` with `--rosemary` profile.
2. Configure:
   - `ROSEMARY_PHYS_BASE` & `ROSEMARY_MEM_SIZE`
   - `ROSEMARY_GICD`, `ROSEMARY_GICR`, `ROSEMARY_TIMEBASE`, `ROSEMARY_VTIMER_INTID`
   - `ROSEMARY_FB`, `ROSEMARY_FB_W`, `ROSEMARY_FB_H`, `ROSEMARY_FB_STRIDE`
   - `ROSEMARY_UFS` base & size
3. Merge `/product` properties from iPhone X (`D22AP`) device tree.

### Step 4: Storage & GPT LUN Configuration
1. Validate UFS initialization in `shim/ufs.c` and XNU driver.
2. Verify GPT partition table LUN on rosemary (fleur uses LUN 2; verify if rosemary is LUN 0 or LUN 2).
3. Ensure iOS root partition points to `userdata`.

### Step 5: Kernel Build & CI Dispatch
1. Dispatch kernel build via `.github/workflows/xnu.yml` against the `rosemary` branch:
   ```sh
   gh workflow run xnu.yml -R kprabhat248/iOS-rose --ref rosemary
   ```
2. Download build artifacts (`xnu-kernel`) into `xnu/out`.

### Step 6: iOS Root & Userland Setup
1. Extract iOS 16.7.16 (20H392) iPhone X IPSW.
2. Generate HFS+ root with `tools/mkiosroot.sh`.
3. Apply iOS system tweaks via `tools/sweet-root-tweaks.py`.
4. Flash root into `userdata`.

### Step 7: Peripherals & Interactive UI
1. Verify console ring buffer.
2. Port/adapt touchscreen driver for rosemary's touch panel.
3. Hook hardware buttons (Volume Up/Down, Power).
4. Validate SpringBoard / backboardd launch.

---

## Current Status (2026-10-25)
- [x] Branch `rosemary` created from `fleur` base.
- [x] Branch pushed to remote `origin/rosemary`.
- [x] Stock `boot.img` & DTB/DTBO extracted from official Indian fastboot ROM on external SSD.
- [x] Step 2: Shim & boot.img builder configured in `shim/build-rosemary.sh` and verified (built `shim/out/shim-rosemary.img` with matching MTK boot header).
- [x] Step 3: Apple Device Tree profile added in `tools/mkadt.py` (`--rosemary`) with 8 CPUs, GICv3, 13 MHz timer, and UFS 2.2 nodes.
- [x] Milestone 1 verified on physical screen:
  - LK enters at EL1 (`boot_el = 1`, `now = 1`).
  - Boot CPU MIDR: `0x411FD050` (Cortex-A55 r1p0).
  - Boot CPU MPIDR: `0x81000000`.
  - Timer CNTFRQ: exactly 13 MHz (`0xC65D40`).
  - MMFR0: `0x01011122` (TGran16 = 0: 16K granule not supported on A55; 4K and 64K supported).
  - Framebuffer: `0x7C010000`, 1080x2400, stride `0x1100` (4352 bytes).
  - PSCI: v1.1 (`0x00010001`), SYSTEM_RESET and CPU_ON supported.
  - DTB patched by LK: `MT6785V/CD`, DRAM `0x40000000` size `0x180000000` (6 GB).
  - UFS: controller at `0x11270000` (size `0x2300`), vcc `0x5B`.
- [x] Milestone 2 verified on physical screen:
  - GICv3 Distributor at `0x0C000000` (IIDR `0x0201543B` = ARM GIC-500) and Redistributor at `0x0C040000`.
  - All 8 CPU redistributors active (`count=00000008`, size `0x00200000`).
  - Secondary cores CPU1 through CPU7 booted via `PSCI_CPU_ON` with `ret=0` (`PSCI_SUCCESS`).
  - Cores reported online in mailbox: CPU1 `0x81000100`, CPU2 `0x81000200`, CPU3 `0x81000300`, CPU4 `0x81000400`, CPU5 `0x81000500`, CPU6 `0x81000600`, CPU7 `0x81000700`.
- [x] Step 5: XNU kernel boot & display geometry:
  - Kernel build CI dispatched & downloaded: GitHub Actions Run ID `40226134257` on ref `rosemary` (commit `7da9f81`, sha256 `866f819d5565828ea6ce379ad65bd60e514e0ed96edd2269b7278202c1a2faa5`).
  - Stride resolution: Reverted stride to exact 4,320 bytes (`1080 * 4 = 4320`). Changing stride to 4,352 bytes (1088 px) caused display shearing into two split columns ("two side double") because Rosemary's AMOLED panel scanline pitch is strictly 1080 pixels (4,320 bytes) without 64-byte padding.
  - MediaTek LK does not support temporary `fastboot boot` (`usb_read failed`), which previously fell back to the older 4,352-stride image on `boot_a`.
  - Storage fix: Set `ufslun=2` in cmdline. MediaTek UFS stores the GPT and `userdata` on LUN 2 (LUN 0 and 1 are 4 MB boot LUNs without a GPT, which caused panic `IOFindBSDRoot: SWEET UFS root ufsroot0 unavailable: 6`).
  - Bootloop cause: after an initial crash, MTK LK marked `slot-retry-count:a: 0`, `slot-unbootable:a: yes`, and switched to `current-slot: b`.
  - Fix applied: erased `misc` partition to clear LK bootctrl state, rebooted bootloader, verified slot reset (`current-slot: a`, `slot-unbootable:a: no`, `retry-count: 7`), re-disabled AVB on `vbmeta_a/system/vendor` (`--disable-verity --disable-verification`), and flashed `shim/out/shim-rosemary.img` (4,320 stride) in 4M sparse chunks (`-S 4M`). Rebooted device.
- [x] Step 5b: Framebuffer stride root cause (boot-log photo, 2026-10-26):
  - Observation: on the physical screen the top ~23 text rows of the XNU boot log render clean (`zone_init: ...`), everything below degenerates into tilted, overlapping diagonal streaks.
  - Measurement: the lower region drifts ~8 px per screen row going down = 32 bytes/row, exactly `4352 - 4320`. The drift is *leftwards*, which means the console writes 4320 while the panel scans 4352.
  - Panel pitch 4352 (0x1100) is corroborated three ways: LK's own milestone-1 report (`stride 0x1100`), `FLEUR_FB_STRIDE = 1088 * 4`, and the measured 32-byte delta.
  - GUESS (not yet re-tested): the earlier "two side double" at 4352 came from a half-applied change — `EARLY_STRIDE` in patches 0010/0012 is compiled into the kernel, so a rebuilt ADT with a stale kernel leaves `sweet_early` and `fbcon` writing different pitches. This time all writers move together and the kernel is rebuilt too.
  - Fix applied: `tools/mkadt.py` `ROSEMARY_FB_STRIDE = 1088 * 4`; patches `0010` (`EARLY_STRIDE` + the two `start.s` asm constants) and `0012` (`EARLY_STRIDE`) → 4352; `shim/build-rosemary.sh` passes `-DFB_STRIDE=4352`. `shim/console.h` is shared with fleur, so `FB_STRIDE` became `#ifndef`-guarded keeping the 4320 default fleur was verified with.
  - `xnu/out/rosemary.adt` rebuilt: `sweet-fbcon` `stride = 0x1100`.
  - Observation: `fleur` (Redmi Note 11S) and `rosemary` (Redmi Note 10S) are both AMOLED; the differences are 90 Hz vs 60 Hz and the physical size/PPI, which is why the panel scan pitch must be taken from LK rather than copied between profiles.
- [x] Step 5c: Kernel rebuilt with the 4352 stride (2026-10-26):
  - Commit `8460763` "rosemary: set every framebuffer writer to the panel's 4352-byte scan pitch" pushed to `origin/rosemary` (`d9a984d..8460763`); it carries the mkadt/patch 0010/patch 0012/build-rosemary.sh edits plus the pre-existing `NOTES.md` and `shim/shim.c` changes.
  - GitHub Actions Run ID `40273678907` on ref `rosemary` — build **completed success** (all steps ✓). The previous kernel in `xnu/out/` was verified to be the 4320 build (sha256 `866f819d5565828ea6ce379ad65bd60e514e0ed96edd2269b7278202c1a2faa5`, matching `xnu/out/SHA256SUMS` and the Step 5 note), so a rebuild was genuinely required rather than optional.
  - Observation: `shim/console.h` and `tools/mkadt.py`'s default (line 33, QEMU/fleur) profile were deliberately left at 4320 — only `build-rosemary.sh` overrides `FB_STRIDE`, so fleur behaviour is preserved. Both patch files still parse (`git apply --stat`).
  - Local pre-flight: `shim.c` + `console.c` compile with *and* without `-DFB_STRIDE=4352` (only the pre-existing `unused function 'mmu_report'` warning); a probe translation unit asserts `FB_STRIDE` resolves to 4352 with `-D` and 4320 by default.
  - Payload header recovered from the existing `xnu/out/rosemary.payload` for the repack: `nsegs=10`, `adt_off=0xfd4f70`, `adt_size=10104`, cmdline `-v debug=0x14e serial=3 cpus=8 sweetfb_native=1 rd=ufsroot0 ufslun=2`; the ADT has **no** `RAMDisk` entry, so `mkpayload.py --ramdisk` must *not* be used.
  - Observation: the only two framebuffer writers are `fbcon` (patch 0003, reads the ADT stride) and `sweet_early` (patches 0010/0012, `EARLY_STRIDE`). Patches 0043/0047/0067 write no framebuffer; `AppleCLCD` (patch 0046) takes `fRowBytes` from `boot_args.Video.v_rowBytes`, which the shim sets from `FB_STRIDE`.
- [x] Step 5d: All artifacts rebuilt and cross-verified at 4352 (2026-10-26):
  - Kernel artifact downloaded from run `40273678907`; sha256 `ab6c8d7477344118d9f867e1f17a0626dcb549941f1297ca2b0ef498272876fc` (matches the artifact's own `SHA256SUMS`; differs from the 4320 build's `866f819d...`, so the rebuild genuinely took).
  - Positive confirmation the 4352 constants compiled in: disassembly of the new kernel shows the `start_first_cpu` band block materialising `x0 = 0x7c9e4000` (= `0x7c010000 + 2368*4352`) with `x4 = #0x1100`, `w1 = #-1`, `x2 = #32`, `x3 = #64`. A lone `mov w9, #0x10e0` elsewhere is a literal in `_vm_packing_pointer_invalid`'s panic path, **not** a framebuffer writer — verified by context.
  - Payload repacked: `tools/mkpayload.py kernel.development.sweet rosemary.adt rosemary.payload --cmdline "-v debug=0x14e serial=3 cpus=8 sweetfb_native=1 rd=ufsroot0 ufslun=2"`; sha256 `2c3482ab...`. `--ramdisk` correctly *not* used (`ramdisk: None`; the ADT has no `RAMDisk` node). Header re-verified from the packed file: `nsegs=10`, cmdline byte-identical, and the **embedded** ADT's `sweet-fbcon` reports `stride = 0x1100`.
  - Shim rebuilt: `shim/build-rosemary.sh "$PWD/xnu/out/rosemary.payload"` (an **absolute** path is required — the script `cd`s into `shim/`, so a repo-relative path fails with `can't open 'xnu/out/rosemary.payload'`). External SSD was re-mounted, so the real stock DTB at `/Volumes/files/rosemary/boot_unpacked/dtb` was used, not the `$MUSI` fallback.
  - Shim stride verified in its own disassembly: 8 sites carry `#0x1100`, **zero** carry `#0x10e0`.
  - Boot image verified end-to-end by unpacking it (`tools/unpack_bootv2.py`): layout is *inverted* from the naive reading — boot.img "kernel" = the gzipped shim (11619 B → 229376 B, sha-matches `shim/out/Image`), boot.img "ramdisk" = the SWEETXNU payload (16611056 B, byte-identical to `xnu/out/rosemary.payload`). The ADT extracted back out of the flashable image reports `stride = 0x1100`, and the 159169 B stock DTB is intact.
  - `shim/out/shim-rosemary.img` sha256 `3085da8a9022ba51c64bca66c57fb472f884d46b0ec6b4cd8dde8276a006affe` (previous 4320 image: `5d375760eac615bc3cc36440709fcd5f178749edfb4a0d73eaa388674c1b3be3`, kept at `/tmp/shim-rosemary.img.bak`).
  - Pre-flash state: `fastboot devices` empty — the phone is not in fastboot mode yet.
- [x] Step 5e: Flashed and rebooted (2026-10-26):
  - Pre-flash slot state recorded: `current-slot: a`, `slot-successful:a: yes`, `slot-unbootable:a: no`, `slot-retry-count:a: 7`, `slot-successful:b: no`, `slot-unbootable:b: no`. Slot `a` was healthy, so any later boot failure is attributable to this image.
  - `fastboot flash boot_a -S 4M shim/out/shim-rosemary.img` → 4 sparse chunks, all `OKAY` (total 0.531 s). The leading `Invalid sparse file format at header magic` is benign: it is fastboot falling back to on-the-fly sparsing of a *raw* (non-sparse) image, not an error — the same message appeared on the previously working flash.
  - Read-back verification **not possible**: this device's fastboot does not support the `fetch` command (`Unable to get max-fetch-size`). Verification therefore rests on the 4/4 `OKAY` writes plus the offline end-to-end unpack check in Step 5d.
  - `fastboot reboot` issued.
- [x] Step 5f: Screen photo analysis & Fleur clean console adoption (2026-10-26):
  - Observation from physical screen photo: moving to 4352 caused "two-side double" (split screen) where lines start on the right and wrap to the left, plus diagonal streaks on top from terminal buffer overflow.
  - Major milestone achieved: XNU booted all the way into userspace and started **PID 1 (`launchd`)**!
  - Panic root cause: `launchd` crashed in userspace (`handle_user_abort` → `exception_triage` → `postsig_locked` → `exit_with_reason` → `proc_exit` → panic).
  - Adopted Fleur's clean console solution (`tools/clean-console.py`):
    - Renamed ADT node `sweet-fbcon` → `sweet-fboff` inside the payload using `tools/clean-console.py`. `fbcon_probe()` never registers, so XNU text console never writes to the framebuffer, completely eliminating diagonal streaks, smears, and double-column shearing.
    - Reverted `FB_STRIDE` to 4320 (`1080 * 4`) in `tools/mkadt.py`, `shim/build-rosemary.sh`, and patches `0010`/`0012`.
    - Shim (`loader.c`) wipes the 31.3 MB framebuffer with `zero64(FB_BASE, 0x1DF0000UL)` right before jumping. The screen starts clean black, and GUI/SpringBoard rendering is left to `AppleCLCD` (patch 0046).
    - Shim disassembly re-verified: all stride sites use `#0x10e0` (4320 bytes).
    - Unpacked verification: `dtb` intact (155 KB), payload ADT contains `sweet-fboff`, `stride = 4320`.
    - Boot image generated: `shim/out/shim-rosemary.img` (16,785,408 bytes).
  - All kernel logs and panic backtraces continue to be saved in the 4 MiB persistent ring buffer in `userdata` (`SWEETLOG`), readable with `tools/sweet-log-pull.sh`.
  - Flash completed (2026-10-26):
    - Slot verification: `current-slot: a`, `slot-unbootable:a: no`, `slot-retry-count:a: 7`.
    - Image sha256: `6a35f8427d207cd220d85dd8cf6ed042a64f4dde17bc060f335d417d89c61bac`.
    - `fastboot flash boot_a -S 4M shim/out/shim-rosemary.img` -> 4/4 sparse chunks `OKAY` (0.520 s).
    - `fastboot reboot` issued successfully.
- [x] Step 5g: Fresh kernel build & clean console package flashed (2026-10-26):
  - GitHub Actions run `40306177352` on ref `rosemary` (commit `fdd9b55`) completed in 7m20s.
  - Downloaded `kernel.development.sweet`: sha256 `f79f5e90de8e41fb5a82e26dc42dbfcd1a1c385e27f2246ab6fc4726bc474a75`.
  - Disassembly of `start_first_cpu` confirmed `#0x10e0` (4320 bytes) at `fffffe000748d114`.
  - Repacked payload with new kernel: `xnu/out/rosemary.payload`.
  - Applied `tools/clean-console.py`: renamed `sweet-fbcon` → `sweet-fboff`.
  - Rebuilt flashable image: `shim/out/shim-rosemary.img` (sha256 `c18fe561448bad2c62e90d63f714b908af99cdca04f3ec0ee0d186895f766ddd`).
  - Unpack verification: payload ADT node `sweet-fboff`, `stride = 4320`, DTB 155 KB intact.
  - Flashed to `boot_a` (4/4 sparse chunks `OKAY`, 0.571s) and issued `fastboot reboot`.
- [x] Step 5h: Fleur-matched 4352-stride clean console image flashed (2026-10-26):
  - Hardware observation confirmed: 4,352 bytes (`1088 * 4`) is the physical panel scan pitch; 4,320 caused diagonal smearing across all lines.
  - Re-aligned setup to Fleur's verified configuration:
    - Stride: 4,352 bytes (`1088 * 4`) across `tools/mkadt.py`, `shim/build-rosemary.sh`, and `shim/loader.c`.
    - Kernel: 4,352 kernel from run `40273678907` (`kernel.development.sweet`, sha256 `ab6c8d7477344118d9f867e1f17a0626dcb549941f1297ca2b0ef498272876fc`).
    - Font scale: `ba->Video.v_depth = 32 | (1 << 16)` (2x font, matching Fleur commit `9aa1b4f`).
    - Clean console: `tools/clean-console.py` renamed `sweet-fbcon` → `sweet-fboff` in ADT to prevent XNU text console from corrupting the screen.
    - Framebuffer wiped: `zero64(FB_BASE, 0x1DF0000UL)` in `shim/loader.c` clears the full 31.3 MB before jumping.
  - Flashable image generated: `shim/out/shim-rosemary.img` (sha256 `717da4be9b4f1314329e95eb3b5d7a20f282c206977d7c0e696856f034004fd1`).
  - Unpack verification: payload ADT node `sweet-fboff`, `stride = 4352`, stock DTB 155 KB intact.
  - Flashed to `boot_a` (4/4 sparse chunks `OKAY`, 0.504 s) and issued `fastboot reboot`.
- [x] Step 5i: Green strip removed, TOPRGU WDT reinforced, CI build dispatched (2026-10-26):
  - Log extraction breakthrough: Pulled 45,167 bytes log from `userdata` (`/dev/block/sdc61`) via recovery ADB using `tools/sweet-log-pull.sh`.
  - Proven facts from log:
    - Root mounted rw from `userdata` LUN 2 (`iOSRoot`).
    - `launchd` started and completed `libignition` stage 7 (`goodbye: ignition sequence complete`).
    - 30+ background system daemons executed (`tccd`, `cloudd`, `mDNSResponder`, `homed`, `coreauthd`, etc.).
    - `SpringBoard` executed! Zero kernel panics or crashes in userspace boot!
  - Root cause of green strip: `sweet_early_mark()` in `0010` was drawing 32 green scanlines (`0xff00ff00u`) and text lines at early boot, which remained frozen on screen when `sweet-fbcon` was disabled.
  - Fix applied:
    - Disabled Stage 0 band drawing in `start.s`.
    - Made `sweet_early_mark` and `sweet_early_putc` immediate returns in `patch 0010` (no green pixels or text ever drawn).
    - Reduced `patch 0012` to a clean no-op (no TTBR0 alias, no `map_final`).
    - Reinforced TOPRGU WDT disable before jumping in `shim/loader.c` (`0x10007000 = 0x22000000`, `0x10007008 = 0x1971`).
    - Fixed macOS BSD `stat` compatibility in `tools/sweet-log-pull.sh`.
    - Committed (`52550b0` and `9e9af4b`), pushed to `origin/rosemary`, and dispatched GitHub Actions run `40316740723`.
- [x] Step 5j: Zero-strip clean kernel image built, flashed and rebooted (2026-10-26):
  - CI Build: Run `40316740723` on commit `9e9af4b` succeeded in 6m49s.
  - Downloaded `kernel.development.sweet`: sha256 `9706ab05b35ba5d1c9ed35b3b8fc4af61325409b9a2e3b4d17d8eeef0903addd`.
  - Disassembly verified:
    - `<_start_first_cpu>`: Stage 0 pixel loop completely removed.
    - `<_sweet_early_mark>`: single `ret` instruction. Zero green pixels or text lines written.
    - `<_sweet_early_putc>`: single `ret` instruction.
  - Stride verified: 4,352 bytes (`1088 * 4`) across ADT, shim, and kernel.
  - TOPRGU WDT disabled before jumping: `*(volatile uint32_t *)0x10007000UL = 0x22000000U`, `0x10007008UL = 0x1971U`.
  - Framebuffer wiped: 31.3 MB cleared to black with `zero64(FB_BASE, 0x1DF0000UL)`.
  - Image built: `shim/out/shim-rosemary.img` (sha256 `49cf76ca5e2abec3b66d6c3b8f03b4e790dbe370db3cb6c27f41b4b637530202`).
  - Flashed to `boot_a` (4/4 sparse chunks `OKAY`, 0.559 s).
  - Switched active slot to `a` (`fastboot set_active a`).
  - Issued `fastboot reboot`.
- [x] Step 5k: Visible text console image with green strip removed flashed (2026-10-26):
  - User requested live on-screen boot text instead of dark screen.
  - Re-enabled `sweet-fbcon` node in ADT (`width = 1080`, `height = 2400`, `stride = 4352`).
  - Kernel: Clean kernel with `sweet_early_mark` and `sweet_early_putc` disabled (`ret`), Stage 0 pixel loop removed.
  - Watchdog: TOPRGU WDT disabled before jump (`0x10007000 = 0x22000000`, `0x10007008 = 0x1971`).
  - Boot image built: `shim/out/shim-rosemary.img` (sha256 `4d03b00db3cfb797823f13ed18b46ccfda8e7e58a365074c03971fa8358acb5d`).
  - Flashed to `boot_a` (4/4 sparse chunks `OKAY`, 0.522 s) and issued `fastboot reboot`.
- [x] Step 5l: `pe_init.c:314` panic root-caused and fixed (2026-10-26):
  - Screen photo showed early panic: `panic(cpu 0 caller 0xfffffe0007aa49f4): pe_init.c:314 Assertion failed: *delta >= 0` (Darwin 22.6.0, XNU-8796.141.3), with fbcon diagonal smear above it.
  - Root cause (verified, not a guess): commit `39acbe9` accidentally deleted `ba->Video.v_height = FB_H;` from `shim/loader.c` while reworking the `v_depth` line. The zeroed boot_args then carried `v_height = 0`; in `PE_init_iokit()` the boot-progress fit loop uses `display_size = v_height` (`0/2 = 0`, condition always true), `*delta` goes negative, and `assert(*delta >= 0)` at `pe_init.c:314` panics before IOKit starts.
  - Fix: restored `ba->Video.v_height = FB_H;` (2400) in `shim/loader.c` with a comment stating the constraint. Kernel/ADT/payload unchanged — no CI rebuild needed.
  - Verification: standalone compile + disassembly shows `mov w10, #0x960; str x10, [x19, #0x48]` (v_height at boot_args offset 0x48, immediately after v_width at 0x40); the same pair confirmed inside the built `shim/out/Image` at offset `0x3dd8`.
  - Rebuilt `shim/out/shim-rosemary.img`: sha256 `15d9c7eec5ad2e50d748f990c8e8520612ac43863283d44ebf95e02fb7a3349a`.
  - Flashed to `boot_a` (4/4 sparse chunks `OKAY`, 0.530 s) and issued `fastboot reboot`. Slot `a` was healthy pre-flash (`slot-unbootable:a: no`, retry-count 5).
- [x] Step 5m: second boot photo analyzed — launchd CS_KILLED panic + fbcon shear (2026-10-26):
  - After the v_height fix the boot passes `PE_init_iokit` and reaches userspace, then panics: `unexpected SIGKILL of launchd ... (CS_KILLED)`. Symbolication against the running kernel (`kernel.development.sweet` sha `9706ab05...`, load base `0xfffffe0007004000`): the panic caller `0xfffffe0007afb710` = `psignal_internal.cold.3` — the kernel panics **by design** when initproc dies by SIGKILL. `CS_KILLED` means AMFI/code-signing killed `launchd`; the exit-reason detail lines (`CRASH launchd[1] ...` from patch 0043) are only in the SWEETLOG ring, so the root cause is not yet determinable offline. The 5i-era boot (kernel `f79f5e90`, fbcon off, 4320) ran launchd to SpringBoard, and commit `9e9af4b` (the only kernel diff since) touches only the early console patches — the kernel is unlikely to be the cause. The fbcon-on console or an on-disk root issue (rw root + SWEETLOG tail writes) are the open suspects; SWEETLOG will discriminate (it holds the exec log and the `CRASH` lines).
  - Shear diagnosis: the flashed payload's ADT was re-verified to carry `sweet-fbcon` `stride = 0x1100` (4352), matching shim (`v_rowBytes`) and kernel, and IOMFB's stub surface also builds from `v_rowBytes` — all writers agree, yet fbcon text still shears while panic-screen text renders clean. This reproduces fleur's pre-clean-console artifact, whose proven fix (Step 5f, verified on both boards) is disabling the framebuffer console: `tools/clean-console.py` renames the ADT node so `fbcon_probe()` never registers. Fleur has never run fbcon-on-screen clean either.
  - Fix built: `tools/clean-console.py` applied → `xnu/out/rosemary-clean.payload` (sha256 `236f63fc3c9f0afc9969080e126cc41d74c2f8c5304da4ff1bdef8bfcbe9b326`); shim rebuilt with the v_height fix (verified `mov w10, #2400; str` at Image offset `0x3dd8`); `shim/out/shim-rosemary.img` sha256 `ee1ff1feaa66eb0075d7f3dd116f254b7adbed44dce3b6dc0b495625ebbc33e6`. End-to-end unpack check: boot.img ramdisk byte-identical to `rosemary-clean.payload`, ADT node `sweet-fboff` present / `sweet-fbcon` gone, stock DTB 159169 B intact.
  - Trade-off (same as fleur): no live boot text on screen (dark screen until GUI/panic output), but the 4 MiB SWEETLOG ring in `userdata` still receives every line (`tools/sweet-log-pull.sh`), and panic screens still display (verified at 5f with `sweet-fboff`).
  - NOT YET FLASHED: no device attached (`fastboot devices` empty at 20:40 local).
- [x] Step 5n: `launchd` CS_KILLED root cause = wrong payload cmdline (2026-10-26):
  - Recovery log pull (`tools/sweet-log-pull.sh` via slot `b` = OrangeFox, `adb root`) returned the **old 5i-era boot log unchanged** (45,167 bytes, `flush #1`) — today's boots never wrote the SWEETLOG ring at all.
  - Decisive evidence in the old log (line 193): the successful boot ran launchd with boot-args `debug=0xc serial=3 cpus=8 keepsyms=1 -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 -wdt_no_pmu sweetfb_native=1 sweetfb_hz=30 usbmap=1 usbg=1`, while every payload packed since Step 5c carried the stripped cmdline `-v debug=0x14e serial=3 cpus=8 sweetfb_native=1 rd=ufsroot0 ufslun=2` (recovered from the 4320-era payload header and reused verbatim).
  - Consequences, all explained: missing `launchd_unsecure_cache=1` → AMFI kills launchd → `unexpected SIGKILL of launchd ... (CS_KILLED)` panic (exit reason namespace 9 = OS_REASON_SIGNAL); missing `-noprogress` → `PE_init_iokit` progress-fit loop → `pe_init.c:314` panic when `v_height` was 0; missing `ufsrw=1 rootrw=1` → `su.writable` false → SWEETLOG thread never starts (why the ring was stale) and root read-only; missing `wdt=-1 -wdt_no_pmu` (shim TOPRGU disable only partially compensates).
  - Fix: repacked `xnu/out/rosemary-verbose.payload` with the full successful cmdline plus `-v` (user-requested verbose console) and `ufslun=2` (rosemary LUN), ADT `sweet-fbcon` enabled (stride 0x1100 verified), kernel `9706ab05` unchanged. sha256 `299863f722e8eefdb3831002e54ca7b54cd364da3f89c15c7bbb76efed527f7f`.
  - Boot image `shim/out/shim-rosemary.img` sha256 `9fc965cd56f2582936bdde205ecd36b56502405b748a4d6916884e3a00d53909`, flashed to `boot_a` (4/4 `OKAY`) after `fastboot set_active a`, `fastboot reboot` issued.
  - Note: fbcon on rosemary shears scrolled text (same artifact fleur's clean-console solution avoids); verbose mode is on at the user's explicit request. The clean-console variant (fbcon off) remains reproducible via `tools/clean-console.py`.
- [x] Step 5o: `initproc failed to start` panic analyzed; crash-time log flush added (2026-10-26):
  - With the full cmdline the boot got further but panicked again. Symbolication of the on-screen backtrace (kernel `9706ab05`, base `0xfffffe0007004000`): `handle_user_abort(+556) → exception_triage → ast_taken_user → bsd_ast → postsig_locked → exit_with_reason → proc_exit → panic`. `_proc_prepareexit` contains both `panic("initproc failed to start")` (when `initproc_spawned` is false) and `panic("initproc exited")` — so launchd was aborted again (same kill path as the CS_KILLED boot) before ever reaching main.
  - The SWEETLOG ring was still stale (header `total 45167, flush #1` = the old 5i boot): the log thread flushes every 1 s and launchd died within ~1 s of the thread starting, so nothing reached `userdata`. The kill reason (`CRASH launchd[1] sig/code/pc/lr/far` lines from patch 0043, printed to console only) was lost.
  - Fix: patch 0047 reworked into `sweet_log_flush_pass()` + exported `sweet_log_flush()`; the thread flushes immediately at start and every second; patch 0043's `sweet_crash_log()` now calls `sweet_log_flush()` synchronously right after printing the CRASH lines, so every future userspace kill reaches the ring. Committed `b5b267c`, CI run `40358983719`.
  - Note: the on-screen panic banner was ambiguous between `initproc failed to start` (read on screen + by user) and the address of a cold panic stub (`proc_exit.cold.1` = `parent child linkage broken`, or an HFS journal stub) — the flushed log on the next panic will settle which nested panic actually fires.
- [x] Step 5p: boot-to-daemons achieved; killer identified as jetsam (2026-10-26):
  - The crash-flush kernel (run `40358983719`) worked: the pulled ring held a **complete boot that ran past launchd, ignition, mount, seputil, obliterator and deep into daemon launches (bluetoothd, fairplayd, remotepairingdeviced)** — the first boot with the full cmdline succeeded. The next boot panicked at launchd again: the panic is **non-deterministic**, a race, not a configuration problem.
  - Panic screen (photo): `CS_KILLED initproc failed to start -- exit reason namespace 2 subcode 0x6` (kernel `proc_handle_critical_exit`, `panic_with_options`). Namespace 2 = `OS_REASON_JETSAM`; subcode 6 = `kMemorystatusKilledFCThrashing` (`JETSAM_REASON_MEMORY_FCTHRASHING`). The earlier `unexpected SIGKILL ... code 0xe` panic = jetsam reason 14 = `SUSTAINED_PRESSURE` (via `psignal_internal` at delivery time). So the VM's filecache/pressure heuristics misfire on this port (4 GB free yet "unhealthy") and jetsam randomly picks launchd as its victim.
  - Why the ring missed the panic: panic-time `kprintf` bypasses `_cnputs` (where patch 0047 hooks), and patch 0043's crash hook sits in the crash-report branch of `proc_prepareexit` — for launchd, `proc_handle_critical_exit` panics earlier, so the hook never runs.
  - Fix (patch `0085-sweet-no-jetsam-initproc`, commit `e12b00f`, CI run `40364932290`):
    1. `memorystatus_kill_proc()` refuses to kill `initproc` (logs `refusing to jetsam initproc (cause %u)`) — pressure kills pick another victim instead of panicking the kernel.
    2. `proc_handle_critical_exit()` prints the sweet crash report (pc/lr/far/reason) and flushes the ring synchronously before the initproc panic, so any future launchd death is fully captured in `userdata`.
  - Observation: `launchd` still logs `Could not opt into 50 MB Jetsam high watermark: 22: Invalid argument` (benign, appears in successful boots too).
- [x] Step 5q: first fully captured launchd crash (2026-10-26):
  - The `proc_handle_critical_exit` hook works: the panicked boot's ring (`total 8443, flush #2`) contains the complete crash report, flushed synchronously before the panic:
    - `pid 1 exited -- exit reason namespace 2 subcode 0xb` (jetsam `VMCOMPRESSOR_THRASHING`)
    - `CRASH launchd[1] sig 11 code 0x20000000b` = SIGSEGV / KERN_INVALID_ADDRESS
    - `pc 0x104add2ac lr 0x104add294 sp 0x16b672fb0 fp 0x16b673010 far 0x52800150510ce1ae` (slide 0, mh 0x10478c000 → pc = launchd+0x3512ac)
    - backtrace all inside launchd: `0x104adbda4 0x104a93b98 0x104a93fd8 0x104a92dec 0x104a90260`
    - died right after `libignition: ignition blob not available`, before the `parameters` print — the good boot (ring, run `40358983719` kernel) passed that exact point.
  - Interpretation: launchd dereferenced a garbage pointer (far is unmapped; looks like packed instruction words). Combined with the earlier jetsam kills for compressor-thrashing (0xb) / FC-thrashing (6) / sustained-pressure (0xe=14) and `VM Swap Subsystem is ON`, the working theory is **swap/compressor I/O corruption or thrash on the UFS-backed root** — random per boot. Not yet proven.
  - No `-no_swap` boot-arg exists in xnu-8796; `vm_compressor` boot-arg exists (mode 2 = no compressor) if the compressor needs to be disabled next.
  - Rebooted into slot `a` again (the race sometimes passes; jetsam gate now protects pid 1 regardless).
- [x] Step 5r: deterministic launchd crash root-caused to on-device root corruption; root reflashed (2026-10-26):
  - Boot D's crash report (run `40364932290` kernel, log pull 5) matched boot C **byte-for-byte in the fault address** (`far 0x52800150510ce1ae`, same libignition point, same backtrace shape, different launchd load address per boot). Identical garbage across boots and kernels = launchd deterministically reading the same corrupted on-disk data — the random-behavior theory is dead; the iOS root in `userdata` contains a corrupted file (far value looks like file content bytes interpreted as a pointer).
  - The corruption was introduced by earlier rw-root boots (HFS+journal writes over the sweet UFS write path; the pristine `rosemary-ios16-root.simg` predates it). The `cpus=6` big.LITTLE experiment image was built (`rosemary-a55only.payload`) but shelved — no longer needed under the corruption theory.
  - Rebuild requested by user; `sudo tools/build_rosemary_root.sh` was not runnable (password required), but the existing pristine `simg` is byte-equivalent to a rebuild (root tweaks unchanged since Oct 18), so it was reflash directly: `fastboot -S 128M flash userdata rosemary-ios16-root.simg` — 89/89 chunks `OKAY`, 345 s (`-S 512M` fails: device `max-download-size` = 0x8000000 = 128 MiB). Rebooted into slot `a` (boot image = no-jetsam kernel `8cf51060`, full cmdline).
  - IMPORTANT follow-up: the write path that corrupted the root is still in play (rw root + per-second SWEETLOG flushes + HFS journal). If the root corrupts again, suspect the concurrent SWEETLOG writer / UFS write reentrancy (patch 0030) and consider `sweetlog=0` or making the log flush take the same path as block I/O.
- [x] Step 5s: pristine root still crashes at the same address — compressor disabled (2026-10-26):
  - Boot E (first boot on the freshly flashed pristine root) panicked identically: `far 0x52800150510ce1ae`, same libignition point, same backtrace shape. The corrupted-on-disk-file theory is dead: the fault is fully deterministic and independent of root contents, kernel build (flushfix vs no-jetsam) and boot number. The far value does not appear in the kernel image, ADT, shim, or payload — it is produced at runtime.
  - pc−mh varies between boots (0x3512ac / 0x3c92ac / 0x4c92ac) while far stays constant — launchd walks slightly different code paths into the same constant garbage value.
  - Top remaining suspect: the VM compressor (runtime mode 4 = `VM_PAGER_COMPRESSOR_NO_SWAP`: compressor active, swap inactive — so "VM Swap Subsystem is ON" is misleading and swap was never the vector). Its thrashing also drives the jetsam kills. A compressor decode/page bug on generic (non-Apple) ARM64 would produce constant garbage content on the same pages every boot, matching the constant far.
  - Experiment flashed: `vm_compressor=64` in the cmdline = `VM_PAGER_NOT_CONFIGURED` (no compressor, no swap; the boot-arg must be a power of two, see `vm_fault_init`). Image sha256 `4d776be06b454fcd05ffd2fd96cda21c5c3247c1a5d4103e7a528f250babc11d`, flashed to `boot_a`, rebooted. Payload `xnu/out/rosemary-nocomp.payload`.
  - Note: `VM_PAGER_NOT_CONFIGURED` sets `vm_config` all-false (no compressor pageout path). With 4 GB RAM and no memory pressure this is viable for bring-up; watch for `vm_pageout` complaints in the log.
- [x] Step 5t: compressor exonerated; crash is a wild jump, pc probe added (2026-10-26):
  - With `vm_compressor=64` (no compressor, no swap) launchd still faults at the identical `far 0x52800150510ce1ae` right after `ignition blob not available`, with no kernel service calls (no AKS, no sandbox ops) in between — the crash is purely userland.
  - Key realization: launchd's binary is only 541 KB (`__TEXT` 0x68000), but the reported pc sits 1.5–5 MB past `mh`, at offsets that shift per boot in identical-structure backtraces (relative frame gaps constant, base shifted by multiples of 0x7C000). The fp chain and pc are therefore **garbage from a corrupt stack**; the only trustworthy datum is the constant non-canonical far — launchd jumped to a constant bogus address and died.
  - The value is not in the kernel, ADT, shim, payloads, or any of the 179k root files (full scan) — it is produced at runtime. The root DMG also has **no dyld shared cache** (`Caches/com.apple.dyld` absent), and the kernel applies no chained-fixup rebasing for static binaries — launchd self-relocates, which is now suspect #1 for producing a constant bad pointer.
  - Added to the crash report (patch 0043, commit `ca1426a`, CI run `40376440022`): dump of the 16 bytes at pc (`code@pc`) and the vm region containing pc (`pc map`, with file offset for file-backed regions) — distinguishes "real code gone wrong" from "wild jump into garbage", and identifies what mapping the pc came from.
- [x] Step 5t: crash isolated to dyld's ProcessConfig init/dump; runtime-generated garbage (2026-10-27):
  - The pc-probe kernel (run `40381637109`) confirmed: `map hdr` filetype 7 = `MH_DYLINKER` — **the pc executes real dyld code**; `code@pc` bytes match dyld's `_configuration_dump+0x3c` (`ldr x26, [x8]`). dyld on iOS 16 is the launch pipeline (`_ignite` → libignition stages → `_arguments_dump` → `_configuration_init` → `_configuration_dump`); launchd's `LC_LOAD_DYLINKER` maps it right after the binary.
  - `_configuration_init` fills the ProcessConfig from sysctls: `security.mac.img4.ignition_blob` (absent on our kernel → "ignition blob not available" ✓ printed), `hw.osenvironment` (absent — our ADT has **no** `/chosen osenvironment` property; kernel returns EINVAL, which dyld explicitly tolerates), `kern.bootargs` parse via `dyld_parse_boot_arg_cstr/int`.
  - The config-dump probe (run `40389623513`) showed the garbage field's context: x8 already held `0x52800150510ce1ae`, and config+0x1a98..0x1ac8 contain **AArch64 instruction fragments (ADRP/ADD/MOVZ pairs)** — runtime-generated corruption in dyld's __DATA/BSS, not present in any file (kernel, ADT, payloads, all 179k root files, dyld itself all scanned), independent of slide, root contents, kernel build, and compressor setting.
  - Working theory: page zero-fill / memory-corruption bug (pmap patches 0006, or decompression) — possibly SMP-related. Boot A (first boot after a fastboot session) passed; all warm panic-reboots since fail with byte-identical garbage — consistent with stale DRAM surviving warm reboots and a zero-fill or coherency defect.
- [x] Step 5u: dyld crash root-caused to stale D-cache; set/way D-cache invalidation added, all 8 CPUs enabled (2026-10-27):
  - `cpus=1` boot (`rosemary12.log`) reproduced the crash identically: `far 0x52800150510ce1ae` at `_configuration_dump+0x3c` (`ldr x26, [x8]`).
  - Decisive root cause: `0x52800150510ce1ae` decodes to two ARM64 instructions: `sub w14, w13, #0x338` (`0x510ce1ae`) followed by `mov w16, #0xa` (`0x52800150`). Dyld expects `this->dyldCache.addr` to be `nullptr` (0) on systems without a shared cache (`Caches/com.apple.dyld` absent). Because dirty L1/L2 data cache lines from prior boots survived warm reset and were never invalidated before MMU enable, stale instruction lines corrupted dyld's BSS/heap. Dyld evaluated `dyldCache.addr != nullptr`, dereferenced it, and crashed with SIGSEGV.
  - Complete architectural D-cache invalidation by set/way (`CLIDR_EL1` -> `CSSELR_EL1` -> `CCSIDR_EL1` -> `dc isw`) implemented:
    1. In `shim/loader.c`: clears CPU 0's D-cache hierarchy before jumping to XNU.
    2. In `xnu/patches/0065-sweet-smp-psci.patch` (`osfmk/arm64/start.s`): clears D-cache before MMU enable on both boot CPU and secondary CPUs 1..7.
  - All 8 CPUs enabled (`cpus=8`) with full system cmdline in `rosemary-verbose.payload`.
  - Shim rebuilt: `shim/out/shim-rosemary.img` (sha256 updated).
- [ ] Next action:
  - Commit changes, dispatch kernel build via `gh workflow run xnu.yml --ref rosemary`, repack payload with new kernel, and flash `shim/out/shim-rosemary.img` to `boot_a`.

## Flash / Recovery Target
- **Target Partition**: `boot_a` (device uses slot `a` for flashing shim / boot images)
- **Fastboot flash command**: `fastboot flash boot_a <image>`
- **Android stock restore**: `fastboot flash boot_a <stock_boot_a.img>`
- `userdata` will be the target for the iOS HFS+ root; all other partitions (bootloaders, recovery, modem, persist) preserved intact.