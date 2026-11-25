# Kernel Experiment Rules - madaraRikudou (Xiaomi Redmi 9A / blossom)

## Hardware & Build Environment
- **Device:** Xiaomi Redmi 9A (`dandelion` / `blossom`), MediaTek Helio G25 (MT6762G, 8x Cortex-A53), 2GB LPDDR4X RAM, eMMC 5.1.
- **Kernel:** Linux 4.19.325 (`arm64`), defconfig: `arch/arm64/configs/blossom_defconfig`.
- **Compiler:** Proton Clang (`-Werror` active; zero unused variables/functions allowed).
- **Target Branch:** `madaraRikudou` ONLY.

## Repo Exploration Rules (Token-Saving for Full-Repo Hunting)
1. **Skip Irrelevant Directories:** Avoid scanning `arch/x86`, `arch/arm`, `arch/mips`, `arch/powerpc`, `Documentation/`, `samples/`, `tools/`, or non-Android/PCI drivers. Focus on `kernel/`, `mm/`, `net/`, `block/`, `fs/`, `arch/arm64/`, and `drivers/` (`misc/mediatek/`, `mmc/`, `cpufreq/`, `devfreq/`, `thermal/`, `irqchip/`).
2. **Hunt Untouched Areas Only & Protect Locked Hunks:** Prioritise untouched subsystems/files, and if a previously modified file needs a new experiment or bugfix, you may edit unrelated sections ONLY if existing tuned blocks/tweaks remain intact (never revert or alter existing `MADARA_LOCK_*` blocks or prior tuning hunks). Do not re-modify already tuned features (CPU/GPU OC, PELT 16ms, UCLAMP, Simple LMK, MGLRU, HZ_250, BLK_WBT, mq-deadline, page_cluster=0, BBR+FQ, tcp_notsent_lowat, BPF_JIT, RT SPI touch, KernelSU/SuSFS) or files listed below unless extending a genuinely new mechanism:
- `CLAUDE.md.bak`
- `apply-madara-patches.sh`
- `arch/arm64/boot/dts/mediatek/mt6765.dts`
- `arch/arm64/configs/blossom_defconfig`
- `block/elevator.c`
- `crypto/lz4.c`
- `drivers/base/power/wakeup.c`
- `drivers/block/zram/zram_drv.c`
- `drivers/input/touchscreen/ft8006s_spi/focaltech_ex_mode.c`
- `drivers/misc/madara_tweaks.c`
- `drivers/misc/mediatek/base/power/ppm_v3/src/mtk_ppm_interface.c`
- `drivers/misc/mediatek/performance/base/utility.c`
- `drivers/misc/mediatek/ppm_v3/src/mtk_ppm_interface.c`
- `drivers/mmc/core/block.c`
- `drivers/mmc/core/queue.c`
- `drivers/power/supply/mtk_basic_charger.c`
- `kernel/sched/cpufreq_schedutil.c`
- `kernel/sched/fair.c`
- `madara-fix.sh`
- `mm/page-writeback.c`
- `mm/vmstat.c`

3. **One Subsystem Per Session:** Pick ONE untouched high-impact subsystem per chat, inspect its actual C source on `madaraRikudou`, explain the bottleneck clearly, and deliver ONE complete self-contained Bash script in the same response.

## Mandatory Bash Script Format
Generate a downloadable script.
- Start the script with exact header lines:
  `# CLAUDE_MADARA_PATCH`
  `# COMMIT: exp(<subsystem>): <short description>`
  `[ "$(git branch --show-current)" = "madaraRikudou" ] || exit 1`
- Apply edits using embedded `python3 - << 'EOF'` with `assert` checks (including verifying any `MADARA_LOCK_START`..`MADARA_LOCK_END` blocks stay unchanged when touching an existing file; avoid fragile multi-line `sed`).
- End with: `git diff --stat && git diff`

## Experimental Notes & Safe Improvisation Guide (MT6765 / Blossom)
A previous experimental build hung at the Redmi boot logo after simultaneous changes to `cpufreq_schedutil.c`, `mmc/core/block.c`, and `base/power/wakeup.c`. Those three files were reset to the `0ee1451` baseline as a clean starting point. You are encouraged to continue experimenting and improvising on these subsystems with the following hardware notes in mind:
- **`kernel/sched/cpufreq_schedutil.c`:** Feel free to tune rate limits (`up_rate_limit_us` / `down_rate_limit_us`) and frequency scaling behavior, while preserving OPP table snapping via `mt_cpufreq_find_close_freq()` before `mt_cpufreq_set_by_wfi_load_cluster()` so MediaTek SSPM receives valid discrete OPP frequencies.
- **`drivers/mmc/core/block.c`:** Feel free to explore eMMC runtime PM and block queue optimizations, while keeping autosuspend delays conservative enough (avoid overly aggressive sub-second values like `200ms`) so `mtk-msdc` completes early partition mounts cleanly.
- **`drivers/base/power/wakeup.c`:** Feel free to experiment with wakelock timeout capping for idle power savings, while ensuring `mod_timer` / `ws->timer` adjustments guard against inactive or early-boot wakeup sources.
