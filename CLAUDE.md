# Kernel Experiment Rules - madaraRikudou (Xiaomi Redmi 9A / blossom)

## Hardware & Build Environment
- **Device:** Xiaomi Redmi 9A (`dandelion` / `blossom`), MediaTek Helio G25 (MT6762G), 2GB LPDDR4X RAM, eMMC 5.1.
- **Kernel:** Linux 4.19.325 (`arm64`), defconfig: `arch/arm64/configs/blossom_defconfig`.
- **Compiler:** Proton Clang (strict `-Werror`; zero unused variables/functions allowed).
- **Target Branch:** `madaraRikudou` ONLY.

## Already Active Tweaks (Do Not Duplicate or Conflict)
- CPU/GPU OC (DTS), PELT 16ms, UCLAMP, Simple LMK, MGLRU, `CONFIG_HZ_300`, `BLK_WBT` + `mq-deadline`, `page_cluster = 0`, TCP `BBR` + `FQ` + `tcp_notsent_lowat = 16384`, `BPF_JIT`, RT SPI touch thread, KernelSU/SuSFS.

## Mandatory Output Rules for Bash Scripts
1. **Read First:** Inspect the exact C/Kconfig/defconfig files on branch `madaraRikudou` via GitHub before writing any script. Use Linux 4.19 APIs only.
2. **One Self-Contained Bash Script:** Output ONE copy-pasteable Bash script to run inside `~/niigo_kernel`.
3. **Branch Guard:** Start the script with `[ "$(git branch --show-current)" = "madaraRikudou" ] || exit 1`.
4. **Safe Patching:** Use embedded `python3 - << 'PY'` with `assert` checks inside the Bash script instead of fragile `sed` commands for multi-line C edits, and finish with `git diff --stat` and `git diff`.
