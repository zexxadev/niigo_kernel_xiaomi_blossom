#!/usr/bin/env bash
# madara-fix.sh
# Perbaikan untuk commit "direct edit" (0f25864) di branch madaraRikudou.
# Jalankan SEKALI di root source kernel (branch madaraRikudou), lalu review `git diff HEAD`.
# Semua edit divalidasi dulu: kalau ada satu pola yang tidak cocok, TIDAK ADA file yang diubah.
set -euo pipefail

BASE=0f2586497a5662179cd50b9e450b7253af67fff3

[ -f Makefile ] && [ -d arch/arm64 ] || { echo "Jalankan dari root source kernel!"; exit 1; }
git cat-file -e "${BASE}^{commit}" 2>/dev/null || { echo "Commit $BASE tidak ditemukan. Jalankan 'git fetch origin' dulu."; exit 1; }
git diff --quiet HEAD -- || { echo "Ada perubahan yang belum di-commit. Commit atau stash dulu."; exit 1; }

echo "== 1. Kembalikan driver touchscreen (+2 file noise) ke kondisi sebelum patch =="
git checkout "${BASE}^" -- \
  drivers/input/touchscreen \
  include/linux/mm.h \
  drivers/misc/mediatek/performance/base/utility.c

echo "== 2. Terapkan perbaikan =="
python3 - <<'PY'
import re, sys

edits = {}  # path -> isi baru (ditulis hanya jika SEMUA edit valid)

def fail(msg):
    sys.exit("GAGAL (tidak ada file yang diubah): " + msg)

def load(path):
    if path in edits:
        return edits[path]
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            return f.read()
    except FileNotFoundError:
        fail(f"file tidak ada: {path}")

def sub1(path, old, new):
    s = load(path)
    n = s.count(old)
    if n != 1:
        fail(f"{path}: pola harus ketemu tepat 1x, ketemu {n}x: {old[:70]!r}")
    edits[path] = s.replace(old, new)

def resub1(path, pattern, repl, flags=0):
    s = load(path)
    new, n = re.subn(pattern, lambda m: repl, s, flags=flags)
    if n != 1:
        fail(f"{path}: regex harus cocok tepat 1x, cocok {n}x: {pattern[:70]!r}")
    edits[path] = new

def tabify(text):
    out = []
    for line in text.split("\n"):
        n = len(line) - len(line.lstrip(" "))
        out.append("\t" * (n // 4) + " " * (n % 4) + line[n:])
    return "\n".join(out)

# ---------------------------------------------------------------- utility.c
p = "drivers/misc/mediatek/performance/base/utility.c"
s = load(p)
if "#include <linux/gfp.h>" not in s:
    m = re.search(r"^#include\b", s, re.M)
    if not m:
        fail(f"{p}: tidak ada baris #include")
    edits[p] = s[:m.start()] + "#include <linux/gfp.h>\n" + s[m.start():]

# ---------------------------------------------------------------- DTS charger
dts = "arch/arm64/boot/dts/mediatek/mt6765.dts"
sub1(dts,
     "\t\tac_charger_current = <2050000>;\n"
     "\t\tac_charger_input_current = <2400000>;\n"
     "\t\tnon_std_ac_charger_current = <2000000>;\n"
     "\t\tcharging_host_charger_current = <2000000>;\n"
     "\t\tta_ac_charger_current = <2050000>;\n",
     "\t\tac_charger_current = <2050000>;\n"
     "\t\tac_charger_input_current = <3200000>;\n"
     "\t\tnon_std_ac_charger_current = <1020000>;\n"
     "\t\tcharging_host_charger_current = <1500000>;\n"
     "\t\tta_ac_charger_current = <3000000>;\n")
sub1(dts,
     "\t\tac_charger_current = <2050000>;\n"
     "\t\tac_charger_input_current = <2400000>;\n"
     "\t\tcharging_host_charger_current = <2000000>;\n",
     "\t\tac_charger_current = <2050000>;\n"
     "\t\tac_charger_input_current = <2400000>;\n"
     "\t\tcharging_host_charger_current = <1500000>;\n")
sub1(dts,
     "\t\tbattery_cv = <4400000>;\n"
     "\t\tmax_charger_voltage = <6500000>;\n"
     "\t\tmin_charger_voltage = <4420000>;\n",
     "\t\tbattery_cv = <4368000>;\n"
     "\t\tmax_charger_voltage = <6500000>;\n"
     "\t\tmin_charger_voltage = <4420000>;\n")
sub1(dts,
     "\t\tjeita_temp_t3_to_t4_cv = <4250000>;\n"
     "\t\tjeita_temp_t3_to_t4_cv_lc = <4100000>;\n",
     "\t\tjeita_temp_t3_to_t4_cv = <4200000>;\n"
     "\t\tjeita_temp_t3_to_t4_cv_lc = <4100000>;\n")

# ------------------------------------------- charger driver: slow charge fix
# Charger tipe USB_FLOAT (non-standard / kabel tanpa data / divider murah)
# sebelumnya hanya dapat 500 mA. Pakai default MTK (1 A). Batas thermal & JEITA
# tetap berlaku karena dihitung sesudah blok ini.
bc = "drivers/power/supply/mtk_basic_charger.c"
sub1(bc,
     "\t} else if (info->chr_type == POWER_SUPPLY_TYPE_USB_FLOAT) {\n"
     "\t\t/* NONSTANDARD_CHARGER */\n"
     "\t\tpdata->input_current_limit =\n"
     "\t\t\tinfo->data.usb_charger_current;\n"
     "\t\tpdata->charging_current_limit =\n"
     "\t\t\tinfo->data.usb_charger_current;\n",
     "\t} else if (info->chr_type == POWER_SUPPLY_TYPE_USB_FLOAT) {\n"
     "\t\t/* NONSTANDARD_CHARGER: 1 A (bukan 500 mA) agar tidak slow charge */\n"
     "\t\tpdata->input_current_limit =\n"
     "\t\t\tNON_STD_AC_CHARGER_CURRENT;\n"
     "\t\tpdata->charging_current_limit =\n"
     "\t\t\tNON_STD_AC_CHARGER_CURRENT;\n")

# JEITA & limit arus jangan dimatikan lewat sysfs saat runtime
resub1("drivers/misc/madara_tweaks.c",
       r"\t/\* Charging & JEITA Runtime Enforcement \*/\n"
       r"\tmadara_write_sysfs\(\"/sys/devices/platform/charger/sw_jeita\", \"0\"\);\n"
       r"\tmadara_write_sysfs\(\"/sys/devices/platform/charger/power_supply/"
       r"mtk-master-charger/input_current_limit\", \"2400000\"\);\n\n",
       "")

# ---------------------------------------------------------------- wakeup.c
wk = "drivers/base/power/wakeup.c"

# (a) buang blocker lama + perbaiki urutan deklarasi
resub1(wk,
       r"static bool madara_is_blocked_wakelock\(const char \*name\)\n\{.*?\n\}\n\n",
       "", flags=re.S)
sub1(wk,
     "\tif (madara_is_blocked_wakelock(ws->name))\n\t\treturn;\n\tunsigned int cec;\n",
     "\tunsigned int cec;\n")

# (b) helper: batasi (cap) lama wakeup source tertentu, jangan diblokir
helper = tabify('''
/*
 * madara: batasi berapa lama wakeup source tertentu boleh menahan sistem
 * tetap bangun.
 *
 * WLAN RX, netlink, sensor, dan epoll sering ditahan jauh lebih lama dari yang
 * dibutuhkan untuk menyerahkan event ke userspace, sehingga SoC tidak masuk
 * deep sleep. Memblokirnya total membuat notifikasi telat, jadi source tetap
 * diaktifkan normal (event tetap terkirim) tetapi dipaksa kadaluarsa dalam
 * waktu singkat. Batas diperbarui oleh setiap event baru, jadi trafik yang
 * terus mengalir tetap menahan sistem bangun.
 *
 * Mengembalikan batas dalam ms, atau 0 jika source tidak dibatasi.
 */
static unsigned int madara_wakelock_cap_ms(const char *name)
{
    if (!name)
        return 0;
    if (!strcmp(name, "wlan_rx_wake") || !strcmp(name, "wlan_wake"))
        return 1000;
    if (!strcmp(name, "wlan_ctrl_wake") || !strcmp(name, "NETLINK"))
        return 500;
    if (!strcmp(name, "SensorService") || !strncmp(name, "eventpoll", 9))
        return 1000;
    return 0;
}

/* Pasang timer batas untuk wakeup source bergaya "stay awake". */
static void madara_cap_wakeup_source(struct wakeup_source *ws)
{
    unsigned int cap = madara_wakelock_cap_ms(ws->name);
    unsigned long expires;

    if (!cap)
        return;

    expires = jiffies + msecs_to_jiffies(cap);
    if (!expires)
        expires = 1;

    mod_timer(&ws->timer, expires);
    ws->timer_expires = expires;
}
''').lstrip("\n")

sub1(wk,
     "\treturn ws->timer.function != pm_wakeup_timer_fn;\n}\n",
     "\treturn ws->timer.function != pm_wakeup_timer_fn;\n}\n\n" + helper.rstrip("\n") + "\n")

# (c) __pm_stay_awake: pasang cap
sub1(wk,
     "\twakeup_source_report_event(ws, false);\n"
     "\tdel_timer(&ws->timer);\n"
     "\tws->timer_expires = 0;\n",
     "\twakeup_source_report_event(ws, false);\n"
     "\tdel_timer(&ws->timer);\n"
     "\tws->timer_expires = 0;\n"
     "\tmadara_cap_wakeup_source(ws);\n")

# (d) pm_wakeup_ws_event: potong msec yang melebihi cap
sub1(wk,
     "\tunsigned long expires;\n",
     "\tunsigned long expires;\n\tunsigned int cap;\n")
sub1(wk,
     "\twakeup_source_report_event(ws, hard);\n\n\tif (!msec) {\n",
     "\twakeup_source_report_event(ws, hard);\n\n"
     "\tcap = msec ? madara_wakelock_cap_ms(ws->name) : 0;\n"
     "\tif (cap && msec > cap)\n"
     "\t\tmsec = cap;\n\n"
     "\tif (!msec) {\n")

# ---------------------------------------------------------------- PPM
# Jangan matikan PPM_POLICY_PWR_THRO (3): itu proteksi baterai (low battery /
# battery OC / dynamic loading). Hanya UT (1) dan FORCE_LIMIT (2) yang dimatikan.
# Nilai OC CPU/GPU tidak diubah sama sekali.
for ppm in ("drivers/misc/mediatek/base/power/ppm_v3/src/mtk_ppm_interface.c",
            "drivers/misc/mediatek/ppm_v3/src/mtk_ppm_interface.c"):
    sub1(ppm,
         "l_pos->policy >= 1 && l_pos->policy <= 3 && l_pos->is_enabled",
         "l_pos->policy >= 1 && l_pos->policy <= 2 && l_pos->is_enabled")
    sub1(ppm,
         "policy_idx >= 1 && policy_idx <= 3",
         "policy_idx >= 1 && policy_idx <= 2")

# ---------------------------------------------------------------- tulis semua
for path, content in edits.items():
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(content)
    print("OK  ", path)
PY

echo "== 3. Hapus skrip patch lama dari repo (berbahaya kalau dijalankan ulang) =="
if [ -f apply-madara-patches.sh ]; then git rm -q -f apply-madara-patches.sh; fi

echo
echo "Selesai. Ringkasan perubahan terhadap HEAD:"
git status --short | sed -n '1,60p'
echo
echo "Review dengan: git diff HEAD --stat"
