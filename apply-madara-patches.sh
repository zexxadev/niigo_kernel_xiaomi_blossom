#!/usr/bin/env bash
# apply-madara-patches.sh
# Skrip SEKALI JALAN: memindahkan patch yang dulu disuntikkan builder ke source kernel.
# Jalankan di root repo kernel (branch rikudouV1.5), lalu review `git diff` sebelum commit.
# JANGAN dijalankan dua kali: patch thermal (+5C) bersifat akumulatif.
set -euo pipefail

[ -f Makefile ] && [ -d arch/arm64 ] || { echo "Jalankan dari root source kernel!"; exit 1; }
python3 - << 'PY'
import glob
import os
import re
import subprocess

def patch_file(path, pattern, repl, desc):
    try:
        with open(path, 'r') as f:
            txt = f.read()
        new_txt, n = re.subn(pattern, repl, txt)
        if n:
            with open(path, 'w') as f:
                f.write(new_txt)
            print(f"Patched {desc} in {path} ({n}x) OK")
    except FileNotFoundError:
        pass

# 1. Scheduler: Optimasi Interactive Tasks & PELT 16ms Half-Life
feat_file = 'kernel/sched/features.h'
with open(feat_file, 'r') as f:
    feat = f.read()
feat, n1 = re.subn(r'(#define\s+SCHED_FEAT_GENTLE_FAIR_SLEEPERS\s+)1\b', r'\g<1>0', feat)
if not n1:
    feat, n1 = re.subn(r'SCHED_FEAT\(\s*GENTLE_FAIR_SLEEPERS\s*,\s*true\s*\)', 'SCHED_FEAT(GENTLE_FAIR_SLEEPERS, false)', feat)
feat, n2 = re.subn(r'(#define\s+SCHED_FEAT_NEXT_BUDDY\s+)0\b', r'\g<1>1', feat)
if not n2:
    feat, n2 = re.subn(r'SCHED_FEAT\(\s*NEXT_BUDDY\s*,\s*false\s*\)', 'SCHED_FEAT(NEXT_BUDDY, true)', feat)
with open(feat_file, 'w') as f:
    f.write(feat)
print(f"Patched Sched Features (GENTLE={n1}, NEXT_BUDDY={n2}) OK")

pelt_gen = 'Documentation/scheduler/sched-pelt.c'
pelt_hdr = 'kernel/sched/sched-pelt.h'
if os.path.exists(pelt_gen) and os.path.exists(pelt_hdr):
    with open(pelt_gen, 'r') as f:
        ptxt = f.read()
    ptxt_new, np = re.subn(r'(#define\s+HALFLIFE\s+)32\b', r'\g<1>16', ptxt)
    if np:
        with open('/tmp/sched-pelt16.c', 'w') as f:
            f.write(ptxt_new)
        subprocess.run(['gcc', '/tmp/sched-pelt16.c', '-lm', '-o', '/tmp/sched-pelt16'], check=True)
        hdr_out = subprocess.check_output(['/tmp/sched-pelt16'], text=True)
        if 'LOAD_AVG_PERIOD 16' in hdr_out:
            with open(pelt_hdr, 'w') as f:
                f.write(hdr_out)
            print("Patched PELT 16ms Half-Life (sched-pelt.h) OK")

# 1b. Touch Polling Rate Boost (~200-240Hz aktif, tetap suspend penuh saat layar mati)
patch_file('drivers/input/evdev.c', r'#define\s+EVDEV_BUF_PACKETS\s+8\b', '#define EVDEV_BUF_PACKETS 32', 'evdev touch buffer 32')
touch_patched = 0
for tp_f in glob.glob('drivers/input/touchscreen/**/*.[ch]', recursive=True):
    with open(tp_f, 'r', errors='ignore') as f:
        ttxt = f.read()
    orig_t = ttxt
    ttxt = re.sub(r'\bmsleep\s*\(\s*(?:10|12|15|16)\s*\)', 'usleep_range(4000, 4500)', ttxt)
    ttxt = re.sub(r'\bmdelay\s*\(\s*(?:10|12|15|16)\s*\)', 'udelay(4000)', ttxt)
    ttxt = re.sub(r'(#define\s+(?:TPD|TOUCH|GTP|FTS|ILITEK|NT36)_[A-Z0-9_]*(?:POLL|INTERVAL|DELAY|RATE)[A-Z0-9_]*\s+)(?:10|12|15|16)\b', r'\g<1>4', ttxt)
    ttxt = re.sub(r'(#define\s+(?:TPD|TOUCH|GTP|FTS|ILITEK|NT36)_[A-Z0-9_]*(?:POLL|INTERVAL|DELAY|RATE)[A-Z0-9_]*\s+)(?:10000|12000|16000|16666)\b', r'\g<1>4000', ttxt)
    if ttxt != orig_t:
        with open(tp_f, 'w') as f:
            f.write(ttxt)
        touch_patched += 1
print(f"Patched Touch Polling Rate Boost in {touch_patched} files OK")

# 2. GPU Overclock PowerVR GE8320 -> 920 MHz
for pattern in ['drivers/misc/mediatek/**/*.[ch]', 'drivers/gpu/**/*.[ch]']:
    for path in glob.glob(pattern, recursive=True):
        if 'cpufreq' in path or 'eem' in path:
            continue
        with open(path, 'r', errors='ignore') as f:
            txt = f.read()
        if not any(k in txt for k in ('GPU_DVFS', 'gpufreq', 'mtk_gpufreq', 'rgx_mtk', 'mfg')):
            continue
        new_txt, n_g = re.subn(
            r'(#define\s+(?:SEG_)?GPU_DVFS_FREQ0\s*\(?\s*)(?:650000|600000|520000)(\s*\)?)',
            r'\g<1>920000\g<2>',
            txt
        )
        if not n_g and ('gpu' in path.lower() or 'mfg' in path.lower()):
            new_txt, n_g = re.subn(r'\b650000\b', '920000', txt)
        if n_g:
            with open(path, 'w') as f:
                f.write(new_txt)
            print(f"Patched GPU OC 920MHz in {path} ({n_g}x) OK")

for dts in glob.glob('arch/arm64/boot/dts/**/*.dts*', recursive=True):
    with open(dts, 'r', errors='ignore') as f:
        d_txt = f.read()
    if '650000000' in d_txt and ('gpu' in d_txt.lower() or 'mfg' in d_txt.lower()):
        d_new, n_dts = re.subn(r'\b650000000\b', '920000000', d_txt)
        if n_dts:
            with open(dts, 'w') as f:
                f.write(d_new)
            print(f"Patched GPU DTS OPP 920MHz in {dts} OK")

# 3. CPU Overclock Little Cluster (1.5 GHz -> 1.8 GHz) & Big Cluster (2.3 GHz)
for cpu_f in glob.glob('drivers/misc/mediatek/base/power/cpufreq_v1/**/*.[ch]', recursive=True):
    patch_file(cpu_f, r'\b1500000\b', '1800000', 'Little CPU OC 1.8GHz')
    patch_file(cpu_f, r'\b2001000\b', '2300000', 'Big CPU OC 2.3GHz')

# 4. Storage Read & RAM Management (MGLRU TTL, Watermark, eMMC CRC Off, Block I/O)
patch_file('mm/vmscan.c', r'\bint\s+vm_swappiness\s*=\s*60\s*;', 'int vm_swappiness = 130;', 'vm_swappiness=130')
patch_file('mm/vmscan.c', r'\bint\s+sysctl_vfs_cache_pressure\s*=\s*100\s*;', 'int sysctl_vfs_cache_pressure = 85;', 'vfs_cache_pressure=85')
patch_file('mm/vmscan.c', r'static\s+unsigned\s+long\s+lru_gen_min_ttl\s+__read_mostly\s*;', 'static unsigned long lru_gen_min_ttl __read_mostly = HZ;', 'MGLRU min_ttl=1000ms')
patch_file('mm/swap.c', r'\bint\s+page_cluster\s*=\s*3\s*;', 'int page_cluster = 0;', 'page-cluster=0')
patch_file('mm/page-writeback.c', r'\bint\s+vm_dirty_ratio\s*=\s*20\s*;', 'int vm_dirty_ratio = 15;', 'dirty_ratio=15')
patch_file('mm/page-writeback.c', r'\bint\s+dirty_background_ratio\s*=\s*10\s*;', 'int dirty_background_ratio = 5;', 'dirty_background_ratio=5')
patch_file('mm/page_alloc.c', r'\bint\s+watermark_scale_factor\s*=\s*10\s*;', 'int watermark_scale_factor = 30;', 'watermark_scale_factor=30')
patch_file('mm/page_alloc.c', r'\bint\s+watermark_boost_factor\s*=\s*15000\s*;', 'int watermark_boost_factor = 0;', 'watermark_boost_factor=0')
patch_file('mm/page_alloc.c', r'\bint\s+user_min_free_kbytes\s*=\s*-1\s*;', 'int user_min_free_kbytes = 16384;', 'user_min_free_kbytes=16384')
patch_file('mm/vmstat.c', r'\bint\s+sysctl_stat_interval\s*=\s*HZ\s*;', 'int sysctl_stat_interval = (10 * HZ);', 'sysctl_stat_interval=10*HZ')
patch_file('include/linux/mm.h', r'#define\s+VM_MAX_READAHEAD\s+\d+', '#define VM_MAX_READAHEAD 128', 'VM_MAX_READAHEAD=128')
patch_file('block/elevator.c', r'elevator_get\(\s*q\s*,\s*"mq-deadline"\s*,\s*false\s*\)', 'NULL', 'blk-mq default none')

for mmc_f in glob.glob('drivers/mmc/core/*.c'):
    patch_file(mmc_f, r'\bbool\s+use_spi_crc\s*=\s*(?:1|true)\s*;', 'bool use_spi_crc = 0;', 'eMMC SPI CRC off')

patch_file('kernel/power/suspend.c', r'\bbool\s+sync_on_suspend\s*=\s*true\s*;', 'bool sync_on_suspend = false;', 'sync_on_suspend=false')
patch_file('kernel/sched/fair.c', r'\bunsigned\s+int\s+sysctl_timer_migration\s*=\s*1\s*;', 'unsigned int sysctl_timer_migration = 0;', 'timer_migration=0')
patch_file('kernel/workqueue.c', r'\bbool\s+wq_power_efficient\s*=\s*IS_ENABLED\(CONFIG_WQ_POWER_EFFICIENT_DEFAULT\)\s*;', 'bool wq_power_efficient = true;', 'wq_power_efficient=true')

# 4b. Geser ambang thermal throttle awal +5C (batas shutdown >=95C tetap utuh)
for th_f in glob.glob('drivers/misc/mediatek/thermal/**/*.[ch]', recursive=True):
    with open(th_f, 'r', errors='ignore') as f:
        ttxt = f.read()
    def bump_trip(m):
        val = int(m.group(2))
        if 45000 <= val <= 85000:
            return f"{m.group(1)}{val + 5000}"
        return m.group(0)
    nttxt, nt = re.subn(r'(\btrip_temp\s*=\s*|\bTHERMAL_TRIP_TEMP\s+)(\d{5})\b', bump_trip, ttxt)
    if nt and nttxt != ttxt:
        with open(th_f, 'w') as f:
            f.write(nttxt)
        print(f"Shifted thermal trip +5C in {th_f} ({nt}x) OK")

# 5. Deep Sleep Wakelock Blocker
wakeup_file = 'drivers/base/power/wakeup.c'
with open(wakeup_file, 'r') as f:
    w_code = f.read()

blocker_fn = (
    'static bool madara_is_blocked_wakelock(const char *name)\n'
    '{\n'
    '\tif (!name)\n'
    '\t\treturn false;\n'
    '\tif (!strcmp(name, "NETLINK") ||\n'
    '\t    !strcmp(name, "wlan_rx_wake") ||\n'
    '\t    !strcmp(name, "wlan_ctrl_wake") ||\n'
    '\t    !strcmp(name, "wlan_wake") ||\n'
    '\t    !strcmp(name, "SensorService") ||\n'
    '\t    !strncmp(name, "eventpoll", 9))\n'
    '\t\treturn true;\n'
    '\treturn false;\n'
    '}\n\n'
)

if 'madara_is_blocked_wakelock' not in w_code:
    w_new, nw = re.subn(
        r'(static\s+void\s+wakeup_source_activate\s*\(\s*struct\s+wakeup_source\s*\*\s*ws\s*\)\s*\{)',
        blocker_fn + r'\1\n\tif (madara_is_blocked_wakelock(ws->name))\n\t\treturn;',
        w_code,
        count=1
    )
    if nw:
        with open(wakeup_file, 'w') as f:
            f.write(w_new)
        print("Patched Deep Sleep Wakelock Blocker OK")

# 5b. Fix Slow Charging (AC, Non-Std AC, Apple 2.1A, SW JEITA CC & CV 4.4V)
for chg_f in glob.glob('drivers/power/supply/mediatek/charger/**/*.[ch]', recursive=True):
    with open(chg_f, 'r', errors='ignore') as f:
        ctxt = f.read()
    orig_c = ctxt

    ctxt = re.sub(r'(#define\s+AC_CHARGER_INPUT_CURRENT\s+)\d+', r'\g<1>2400000', ctxt)
    ctxt = re.sub(r'(#define\s+AC_CHARGER_CURRENT\s+)\d+', r'\g<1>2050000', ctxt)
    ctxt = re.sub(r'(#define\s+NON_STD_AC_CHARGER_CURRENT\s+)\d+', r'\g<1>2000000', ctxt)
    ctxt = re.sub(r'(#define\s+CHARGING_HOST_CHARGER_CURRENT\s+)\d+', r'\g<1>2000000', ctxt)
    ctxt = re.sub(r'(#define\s+APPLE_2_1A_CHARGER_CURRENT\s+)\d+', r'\g<1>2050000', ctxt)
    ctxt = re.sub(r'(#define\s+USB_CHARGER_CURRENT\s+)\d+', r'\g<1>1000000', ctxt)

    ctxt = re.sub(r'(->ac_charger_input_current\s*=\s*)\d+;', r'\g<1>2400000;', ctxt)
    ctxt = re.sub(r'(->ac_charger_current\s*=\s*)\d+;', r'\g<1>2050000;', ctxt)
    ctxt = re.sub(r'(->non_std_ac_charger_current\s*=\s*)\d+;', r'\g<1>2000000;', ctxt)
    ctxt = re.sub(r'(->charging_host_charger_current\s*=\s*)\d+;', r'\g<1>2000000;', ctxt)
    ctxt = re.sub(r'(->apple_2_1a_charger_current\s*=\s*)\d+;', r'\g<1>2050000;', ctxt)

    ctxt = re.sub(r'(#define\s+BATTERY_CV\s+)\d+', r'\g<1>4400000', ctxt)
    ctxt = re.sub(r'(#define\s+JEITA_TEMP_T1_TO_T2_CC\s+)\d+', r'\g<1>2050000', ctxt)
    ctxt = re.sub(r'(#define\s+JEITA_TEMP_T2_TO_T3_CC\s+)\d+', r'\g<1>2050000', ctxt)
    ctxt = re.sub(r'(#define\s+JEITA_TEMP_T3_TO_T4_CC\s+)\d+', r'\g<1>1500000', ctxt)
    ctxt = re.sub(r'(#define\s+JEITA_TEMP_T1_TO_T2_CV\s+)\d+', r'\g<1>4400000', ctxt)
    ctxt = re.sub(r'(#define\s+JEITA_TEMP_T2_TO_T3_CV\s+)\d+', r'\g<1>4400000', ctxt)
    ctxt = re.sub(r'(#define\s+JEITA_TEMP_T3_TO_T4_CV\s+)\d+', r'\g<1>4250000', ctxt)

    ctxt = re.sub(r'(->battery_cv\s*=\s*)\d+;', r'\g<1>4400000;', ctxt)
    ctxt = re.sub(r'(->jeita_temp_t1_to_t2_cc\s*=\s*)\d+;', r'\g<1>2050000;', ctxt)
    ctxt = re.sub(r'(->jeita_temp_t2_to_t3_cc\s*=\s*)\d+;', r'\g<1>2050000;', ctxt)
    ctxt = re.sub(r'(->jeita_temp_t3_to_t4_cc\s*=\s*)\d+;', r'\g<1>1500000;', ctxt)
    ctxt = re.sub(r'(->jeita_temp_t1_to_t2_cv\s*=\s*)\d+;', r'\g<1>4400000;', ctxt)
    ctxt = re.sub(r'(->jeita_temp_t2_to_t3_cv\s*=\s*)\d+;', r'\g<1>4400000;', ctxt)
    ctxt = re.sub(r'(->jeita_temp_t3_to_t4_cv\s*=\s*)\d+;', r'\g<1>4250000;', ctxt)

    if ctxt != orig_c:
        with open(chg_f, 'w') as f:
            f.write(ctxt)
        print(f"Patched MTK charger & JEITA CC/CV in {chg_f} OK")

for dts_f in glob.glob('arch/arm64/boot/dts/mediatek/*.dts*', recursive=True):
    with open(dts_f, 'r', errors='ignore') as f:
        dtxt = f.read()
    orig_d = dtxt
    dtxt = re.sub(r'(ac_charger_input_current\s*=\s*<)\d+(>;)', r'\g<1>2400000\g<2>', dtxt)
    dtxt = re.sub(r'(ac_charger_current\s*=\s*<)\d+(>;)', r'\g<1>2050000\g<2>', dtxt)
    dtxt = re.sub(r'(non_std_ac_charger_current\s*=\s*<)\d+(>;)', r'\g<1>2000000\g<2>', dtxt)
    dtxt = re.sub(r'(charging_host_charger_current\s*=\s*<)\d+(>;)', r'\g<1>2000000\g<2>', dtxt)
    dtxt = re.sub(r'(apple_2_1a_charger_current\s*=\s*<)\d+(>;)', r'\g<1>2050000\g<2>', dtxt)
    dtxt = re.sub(r'(battery_cv\s*=\s*<)\d+(>;)', r'\g<1>4400000\g<2>', dtxt)
    dtxt = re.sub(r'(jeita_temp_t1_to_t2_cc\s*=\s*<)\d+(>;)', r'\g<1>2050000\g<2>', dtxt)
    dtxt = re.sub(r'(jeita_temp_t2_to_t3_cc\s*=\s*<)\d+(>;)', r'\g<1>2050000\g<2>', dtxt)
    dtxt = re.sub(r'(jeita_temp_t3_to_t4_cc\s*=\s*<)\d+(>;)', r'\g<1>1500000\g<2>', dtxt)
    dtxt = re.sub(r'(jeita_temp_t1_to_t2_cv\s*=\s*<)\d+(>;)', r'\g<1>4400000\g<2>', dtxt)
    dtxt = re.sub(r'(jeita_temp_t2_to_t3_cv\s*=\s*<)\d+(>;)', r'\g<1>4400000\g<2>', dtxt)
    dtxt = re.sub(r'(jeita_temp_t3_to_t4_cv\s*=\s*<)\d+(>;)', r'\g<1>4250000\g<2>', dtxt)
    if dtxt != orig_d:
        with open(dts_f, 'w') as f:
            f.write(dtxt)
        print(f"Patched DTS charger & JEITA CC/CV limit in {dts_f} OK")

# 6. Suntikkan helper madara_disable_ppm_policies() & lock policy 1-3 di mtk_ppm_interface.c
for ppm_f in glob.glob('drivers/misc/mediatek/**/ppm_v3/src/mtk_ppm_interface.c', recursive=True):
    with open(ppm_f, 'r', errors='ignore') as f:
        ptxt = f.read()
    if 'ppm_policy_status_proc_show' in ptxt and 'madara_disable_ppm_policies' not in ptxt:
        helper_fn = (
            'void madara_disable_ppm_policies(void)\n'
            '{\n'
            '\tstruct ppm_policy_data *l_pos;\n'
            '\tbool changed = false;\n\n'
            '\tppm_lock(&ppm_main_info.lock);\n'
            '\tlist_for_each_entry(l_pos, &ppm_main_info.policy_list, link) {\n'
            '\t\tif (l_pos->policy >= 1 && l_pos->policy <= 3 && l_pos->is_enabled) {\n'
            '\t\t\tppm_lock(&l_pos->lock);\n'
            '\t\t\tl_pos->is_enabled = false;\n'
            '\t\t\tif (l_pos->status_change_cb)\n'
            '\t\t\t\tl_pos->status_change_cb(false);\n'
            '\t\t\tppm_unlock(&l_pos->lock);\n'
            '\t\t\tchanged = true;\n'
            '\t\t}\n'
            '\t}\n'
            '\tppm_unlock(&ppm_main_info.lock);\n'
            '\tif (changed)\n'
            '\t\tmt_ppm_main();\n'
            '}\n'
            'EXPORT_SYMBOL(madara_disable_ppm_policies);\n\n'
        )
        ptxt = ptxt.replace('static int ppm_policy_status_proc_show', helper_fn + 'static int ppm_policy_status_proc_show', 1)
        ptxt = re.sub(
            r'(if\s*\(enabled\s*>\s*1\)\s*enabled\s*=\s*1;)',
            r'\1\n\t\tif (policy_idx >= 1 && policy_idx <= 3)\n\t\t\tenabled = 0;',
            ptxt,
            count=1
        )
        with open(ppm_f, 'w') as f:
            f.write(ptxt)
        print(f"Patched madara_disable_ppm_policies in {ppm_f} OK")

# Fix missing linux/gfp.h in MTK performance utility.c
util_c = 'drivers/misc/mediatek/performance/base/utility.c'
try:
    with open(util_c, 'r') as f:
        utxt = f.read()
    if '#include <linux/gfp.h>' not in utxt:
        utxt = '#include <linux/gfp.h>\n' + utxt
        with open(util_c, 'w') as f:
            f.write(utxt)
        print('Patched linux/gfp.h in utility.c OK')
except FileNotFoundError:
    pass

# Ensure read_ahead_kb sysfs attribute is writable (0644 instead of 0444)
blk_sysfs = 'block/blk-sysfs.c'
try:
    with open(blk_sysfs, 'r') as f:
        btxt = f.read()
    btxt_new, n = re.subn(
        r'QUEUE_RO_ENTRY\(\s*queue_read_ahead\s*,\s*"read_ahead_kb"\s*\)',
        '__ATTR(read_ahead_kb, 0644, queue_read_ahead_show, queue_read_ahead_store)',
        btxt
    )
    if n == 0 and 'queue_read_ahead' in btxt:
        btxt_new = re.sub(r'(\bqueue_read_ahead_entry\.attr\.mode\s*=\s*)0444', r'\g<1>0644', btxt)
        if btxt_new == btxt:
            btxt_new = re.sub(r'(QUEUE_RO_ENTRY\([^)]*read_ahead_kb[^)]*\))', lambda m: m.group(0).replace('0444', '0644'), btxt)
    if btxt_new != btxt:
        with open(blk_sysfs, 'w') as f:
            f.write(btxt_new)
        print('Patched read_ahead_kb sysfs mode to 0644 OK')
except FileNotFoundError:
    pass

PY

# 7. Buat driver madara_tweaks.c (Fast Storage Read + RAM + CPU + Power Lock)
cat << 'EOF' > drivers/misc/madara_tweaks.c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/string.h>
#include <linux/workqueue.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <net/net_namespace.h>
#include <net/tcp.h>

extern void __weak madara_disable_ppm_policies(void);

extern int vm_swappiness;
static int madara_pass;
static struct delayed_work madara_work;

static void madara_write_sysfs(const char *path, const char *val)
{
	struct file *fp;
	loff_t pos = 0;
	mm_segment_t old_fs = get_fs();

	set_fs(KERNEL_DS);
	fp = filp_open(path, O_WRONLY, 0);
	if (!IS_ERR(fp)) {
		kernel_write(fp, val, strlen(val), &pos);
		filp_close(fp, NULL);
	}
	set_fs(old_fs);
}

static void madara_apply_tweaks(struct work_struct *work)
{
	vm_swappiness = 130;
	tcp_set_default_congestion_control(&init_net, "bbr");

	if (madara_disable_ppm_policies)
		madara_disable_ppm_policies();

	/* Storage Read & Low-Latency Block Queue */
	madara_write_sysfs("/sys/block/mmcblk0/queue/scheduler", "none");
	madara_write_sysfs("/sys/block/mmcblk0/queue/read_ahead_kb", "128");
	madara_write_sysfs("/sys/block/mmcblk0/queue/iostats", "0");
	madara_write_sysfs("/sys/block/mmcblk0/queue/add_random", "0");
	madara_write_sysfs("/sys/block/mmcblk0/queue/rq_affinity", "2");

	/* RAM Management (2GB + ZRAM LZ4) */
	madara_write_sysfs("/proc/sys/vm/vfs_cache_pressure", "85");
	madara_write_sysfs("/proc/sys/vm/watermark_scale_factor", "30");
	madara_write_sysfs("/proc/sys/vm/watermark_boost_factor", "0");
	madara_write_sysfs("/proc/sys/vm/min_free_kbytes", "16384");

	/* Interactive CPU Boost + Fast Down-Ramp untuk Efisiensi Daya */
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/schedutil/up_rate_limit_us", "500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/schedutil/down_rate_limit_us", "2500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/schedutil/hispeed_freq", "2300000");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/schedutil/hispeed_load", "78");

	/* Charging & JEITA Runtime Enforcement */
	madara_write_sysfs("/sys/devices/platform/charger/sw_jeita", "0");
	madara_write_sysfs("/sys/devices/platform/charger/power_supply/mtk-master-charger/input_current_limit", "2400000");

	/* Power Efficient Workqueues */
	madara_write_sysfs("/sys/module/workqueue/parameters/power_efficient", "Y");

	/* Network */
	madara_write_sysfs("/proc/sys/net/ipv4/tcp_low_latency", "1");
	madara_write_sysfs("/proc/sys/net/ipv4/tcp_fastopen", "3");

	madara_pass++;
	if (madara_pass == 1)
		schedule_delayed_work(&madara_work, msecs_to_jiffies(35000));
	pr_info("madara_tweaks: pass %d applied\n", madara_pass);
}

static int madara_status_show(struct seq_file *m, void *v)
{
	if (madara_pass >= 2)
		seq_puts(m, "active (locked)\n");
	else if (madara_pass == 1)
		seq_puts(m, "active (pass 1)\n");
	else
		seq_puts(m, "pending\n");
	return 0;
}

static int madara_status_open(struct inode *inode, struct file *file)
{
	return single_open(file, madara_status_show, NULL);
}

static const struct file_operations madara_status_fops = {
	.owner = THIS_MODULE,
	.open = madara_status_open,
	.read = seq_read,
	.llseek = seq_lseek,
	.release = single_release,
};

static int __init madara_tweaks_init(void)
{
	proc_create("madara_status", 0444, NULL, &madara_status_fops);
	INIT_DELAYED_WORK(&madara_work, madara_apply_tweaks);
	schedule_delayed_work(&madara_work, msecs_to_jiffies(25000));
	return 0;
}
late_initcall(madara_tweaks_init);
EOF
grep -q 'madara_tweaks.o' drivers/misc/Makefile || echo 'obj-y += madara_tweaks.o' >> drivers/misc/Makefile
