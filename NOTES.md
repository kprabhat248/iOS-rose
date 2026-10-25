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
- [ ] Next action: Device test of diagnostic shim (`fastboot flash boot_a shim/out/shim-rosemary.img`) to verify early framebuffer console & SMP bringup.


---

## Flash / Recovery Target
- **Target Partition**: `boot_a` (device uses slot `a` for flashing shim / boot images)
- **Fastboot flash command**: `fastboot flash boot_a <image>`
- **Android stock restore**: `fastboot flash boot_a <stock_boot_a.img>`
- `userdata` will be the target for the iOS HFS+ root; all other partitions (bootloaders, recovery, modem, persist) preserved intact.