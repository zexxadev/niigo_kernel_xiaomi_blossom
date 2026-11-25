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
	madara_write_sysfs("/sys/block/mmcblk0/queue/scheduler", "mq-deadline");
	madara_write_sysfs("/sys/block/mmcblk0/queue/read_ahead_kb", "128");
	madara_write_sysfs("/sys/block/mmcblk0/queue/iostats", "0");
	madara_write_sysfs("/sys/block/mmcblk0/queue/add_random", "0");
	madara_write_sysfs("/sys/block/mmcblk0/queue/rq_affinity", "2");

	/* RAM Management (2GB + ZRAM LZ4) */
	madara_write_sysfs("/proc/sys/vm/vfs_cache_pressure", "85");
	madara_write_sysfs("/proc/sys/vm/watermark_scale_factor", "30");
	madara_write_sysfs("/proc/sys/vm/watermark_boost_factor", "0");
	madara_write_sysfs("/proc/sys/vm/min_free_kbytes", "16384");
	/* swap ke ZRAM: jangan baca-depan 8 halaman, hanya menambah latensi */
	madara_write_sysfs("/proc/sys/vm/page-cluster", "0");

	/*
	 * schedutil di kernel ini hanya punya up/down_rate_limit_us (tidak ada hispeed_*).
	 * Tulis ke jalur global dan per-policy (policy0 = LL, policy4 = L); jalur yang
	 * tidak ada diabaikan begitu saja.
	 */
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/schedutil/up_rate_limit_us", "500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/schedutil/down_rate_limit_us", "2500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/policy0/schedutil/up_rate_limit_us", "500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us", "2500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/policy4/schedutil/up_rate_limit_us", "500");
	madara_write_sysfs("/sys/devices/system/cpu/cpufreq/policy4/schedutil/down_rate_limit_us", "2500");

	/* Power Efficient Workqueues */
	madara_write_sysfs("/sys/module/workqueue/parameters/power_efficient", "Y");

	/* Network */
	madara_write_sysfs("/proc/sys/net/ipv4/tcp_fastopen", "3");
	/* jangan turunkan cwnd setelah koneksi diam: burst pertama langsung cepat */
	madara_write_sysfs("/proc/sys/net/ipv4/tcp_slow_start_after_idle", "0");
	/* jangan pakai metrik lama saat pindah WiFi <-> data seluler */
	madara_write_sysfs("/proc/sys/net/ipv4/tcp_no_metrics_save", "1");
	/* atasi PMTU blackhole di jaringan seluler */
	madara_write_sysfs("/proc/sys/net/ipv4/tcp_mtu_probing", "1");

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
