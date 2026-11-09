// SPDX-License-Identifier: GPL-2.0
/*
 * Write the SMP2P "sleepstate" item towards the ADSP the way Windows does
 * (qcsubsys8380.sys, callback \Callback\QcModernStandby):
 *
 *   ADSP start / Modern Standby exit -> 0x1000   (bit 12 = APSS awake)
 *   Modern Standby entry             -> 0x0000
 *
 * The ADSP side is sns_remote_proc_state_sensor.c (extractu(value, 1, 12)),
 * consumed by sns_client_manager.  See docs/adsp-modern-standby-messages.md,
 * sections 4.3 and 5.1.  UNTESTED on hardware; polarity of bit 12 is inferred.
 *
 * Needs an outbound SMP2P entry named "sleepstate" in the smp2p-adsp node,
 * see adsp-sleepstate.dtsi.
 *
 * Manual control without suspending:
 *   echo 0 > /sys/module/asus_adsp_sleepstate/parameters/awake    (APSS "asleep")
 *   echo 1 > /sys/module/asus_adsp_sleepstate/parameters/awake    (APSS "awake")
 */
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/notifier.h>
#include <linux/platform_device.h>
#include <linux/soc/qcom/smem_state.h>
#include <linux/suspend.h>

#define SLEEPSTATE_AWAKE	0x1000	/* bit 12 */
#define SLEEPSTATE_ALL		0xffffffffu

struct ss {
	struct qcom_smem_state *state;
	struct notifier_block nb;
	bool awake;
};

static struct ss *g_ss;

static int ss_write(struct ss *s, bool awake)
{
	int ret = qcom_smem_state_update_bits(s->state, SLEEPSTATE_ALL,
					      awake ? SLEEPSTATE_AWAKE : 0);

	if (!ret)
		s->awake = awake;
	return ret;
}

static int ss_pm_notify(struct notifier_block *nb, unsigned long ev, void *unused)
{
	struct ss *s = container_of(nb, struct ss, nb);

	switch (ev) {
	case PM_SUSPEND_PREPARE:
		ss_write(s, false);
		break;
	case PM_POST_SUSPEND:
		ss_write(s, true);
		break;
	}
	return NOTIFY_DONE;
}

static int awake_set(const char *val, const struct kernel_param *kp)
{
	bool v;
	int ret = kstrtobool(val, &v);

	if (ret)
		return ret;
	if (!g_ss)
		return -ENODEV;
	return ss_write(g_ss, v);
}

static int awake_get(char *buf, const struct kernel_param *kp)
{
	return sysfs_emit(buf, "%d\n", g_ss ? g_ss->awake : -1);
}

static const struct kernel_param_ops awake_ops = {
	.set = awake_set,
	.get = awake_get,
};
module_param_cb(awake, &awake_ops, NULL, 0644);
MODULE_PARM_DESC(awake, "Write 0/1 to the ADSP sleepstate SMP2P item (0 = APSS asleep, 0x1000 = awake)");

static int ss_probe(struct platform_device *pdev)
{
	struct ss *s;
	unsigned int bit;
	int ret;

	s = devm_kzalloc(&pdev->dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;

	s->state = qcom_smem_state_get(&pdev->dev, "sleepstate", &bit);
	if (IS_ERR(s->state))
		return dev_err_probe(&pdev->dev, PTR_ERR(s->state), "no sleepstate smem-state\n");

	s->nb.notifier_call = ss_pm_notify;
	ret = register_pm_notifier(&s->nb);
	if (ret) {
		qcom_smem_state_put(s->state);
		return ret;
	}

	platform_set_drvdata(pdev, s);
	g_ss = s;
	/* Windows writes 0x1000 as soon as the ADSP is online. */
	return ss_write(s, true);
}

static void ss_remove(struct platform_device *pdev)
{
	struct ss *s = platform_get_drvdata(pdev);

	g_ss = NULL;
	unregister_pm_notifier(&s->nb);
	qcom_smem_state_put(s->state);
}

static const struct of_device_id ss_of_match[] = {
	{ .compatible = "asus,adsp-sleepstate" },
	{ }
};
MODULE_DEVICE_TABLE(of, ss_of_match);

static struct platform_driver ss_driver = {
	.probe = ss_probe,
	.remove = ss_remove,
	.driver = {
		.name = "asus-adsp-sleepstate",
		.of_match_table = ss_of_match,
	},
};
module_platform_driver(ss_driver);

MODULE_DESCRIPTION("ADSP SMP2P sleepstate writer (Windows QcModernStandby behaviour)");
MODULE_LICENSE("GPL");
