# iOS 16 on rosemary (Redmi Note 10S, MT6785) - working notes

## Goal
Port Apple's XNU kernel (iOS 16 generation) and the iOS 16.7.16 userland stack to the Redmi Note 10S "rosemary" (MediaTek Helio G95 / MT6785), building upon the work from `sweet` and `fleur`.

## Branch Information
- **Branch**: `rosemary` (branched from `fleur` at commit `9c40e1a`)
- **Remote**: `origin/rosemary` (tracked)

---

## Hardware Overview & Comparison

| Component | Redmi Note 11S ("fleur") | Redmi Note 10S ("rosemary") | Bring-up Notes |
|-----------|--------------------------|-----------------------------|----------------|
| **SoC** | MediaTek Helio G96 (MT6781) | MediaTek Helio G95 (MT6785) | MTK 64-bit ARMv8.2-A |
| **CPU Cluster** | 2× Cortex-A76 + 6× Cortex-A55 | 2× Cortex-A76 + 6× Cortex-A55 | 8 cores, PSCI 1.1 CPU_ON via SMC |
| **RAM** | 6 GB / 8 GB LPDDR4X | 6 GB / 8 GB LPDDR4X | DRAM base `0x40000000` |
| **Display** | 1080×2400 AMOLED (90Hz) | 1080×2400 AMOLED (60Hz) | LK framebuffer carve-out |
| **GIC** | GICv3 (GICD `0x0C000000`, GICR `0x0C040000`) | GICv3 (Check DTB: GICD `0x0C000000`, GICR `0x0C040000`) | Verify PPIs & INTIDs in stock DT |
| **Timer** | 13 MHz (`0xC65D40`) | 13 MHz (standard MTK ARM timer) | Verify CNTFRQ_EL0 |
| **Storage** | UFS 2.2 (`0x11270000`) | UFS 2.2 (MTK UFSHCI) | Target iOS root in `userdata` |
| **PMIC** | MT6358 / MT6366 | MT6359 | Power/Vol keys via PMIC/GPIO |
| **Touch** | FocalTech FTS (I2C) | FocalTech / Goodix / Novatek | Check Android DT for I2C bus & IRQ |
| **Bootloader** | MediaTek Little Kernel (LK) | MediaTek Little Kernel (LK) | LK fastboot / `boot_b` flashing |

---

## Step-by-Step Bring-up Roadmap for Rosemary

### Step 1: Device Inspection & Backup
1. **Stock Partition Backup**:
   - Backup `persist`, `boot`, `dtbo`, `vbmeta`, `modemst1`, `modemst2`, `fsg`, `fsc`.
   - Never commit device backups or calibration data to git.
2. **Device Tree Extraction**:
   - Unpack stock `boot.img` using `tools/unpack_bootv2.py` or extract `dtb` from device.
   - Decompile `dtb` to `.dts` (`dtc -I dtb -O dts -o rosemary.dts stock_dtb`).
   - Extract exact hardware offsets: GIC distributor/redistributor, timer frequency, framebuffer base/size/stride, UFS HCI base, I2C touch controller and GPIO pins.

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
- [ ] Next action: Provide stock `boot.img` or DTB dump from Redmi Note 10S to extract hardware nodes and configure `shim/build-rosemary.sh` and `mkadt.py`.

---

## Flash / Recovery Target
- **Target Partition**: `boot_a` (device uses slot `a` for flashing shim / boot images)
- **Fastboot flash command**: `fastboot flash boot_a <image>`
- **Android stock restore**: `fastboot flash boot_a <stock_boot_a.img>`
- `userdata` will be the target for the iOS HFS+ root; all other partitions (bootloaders, recovery, modem, persist) preserved intact.