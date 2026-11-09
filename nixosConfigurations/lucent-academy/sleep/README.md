# Vivobook S15 CXSD experiment (Linux 7.3, EL1)

Sources: justririll/x1e-sleep at `4e84b60eb073e76f8f7190a168c90c0d869b1326`,
vanilla `linux-7.3.tar.xz`, and BurninChrome/vivobook-s15-fedora at
`c35ad9447dcc0883127de50edab1fb3e54f05334`.

This is an opt-in experiment, not a measured power result for this machine.
No kernel/module compilation or deployment was performed while preparing it.
The existing EC driver and firmware remain unchanged. The eDP regulator fix
is managed separately by `hardware.vivobook-s15.panelPowerOff`.

## Enable in a separate boot entry

Add `./sleep.nix` to the host's imports, then:

```nix
specialisation.cxsd.configuration = {
  system.nixos.tags = [ "cxsd" ];
  hardware.vivobook-s15.deepSleep.enable = true;
  hardware.vivobook-s15.panelPowerOff = true;
};
```

The module defaults `ignoreUnused` to false and asserts it is false. It does
not enable the eDP change itself. Disabled, it leaves the kernel unchanged.

`deepSleep.adspPowerLimits` defaults true; `adspSleepstate` and `pcieGen1Vote`
default false. AOSD is always inhibited when this experiment is enabled;
there is deliberately no default full-AOSD mode. The source project reports
hard resets roughly hourly with AOSD enabled and ~0.17 W with CXSD-only on
its EL2 setup. That reset has not been reproduced or ruled out at EL1.

## Patch/module audit

Paths and line numbers below refer to pristine v7.3 unless otherwise stated.
GitHub compare API confirmed all seven listed upstream commits are ancestors
of `v7.3` (merge-base equals the queried commit, compare status `ahead`).

| x1e-sleep item | Status here / evidence / action |
| --- | --- |
| `qebspil/0001-pil-send-AOSS-load_state-off-on-before-starting-ADSP.patch` | Not applicable: no UEFI qebspil DSP startup. Linux `drivers/remoteproc/qcom_q6v5.c:24,89,117` already sends load_state on/off through QMP. |
| `drm-msm-a6xx-fix-stale-rpmh-votes.patch` | Already in v7.3, `d9108bfdb746edacdb05bd27959a4ae63c6c7f3f`; `drivers/gpu/drm/msm/adreno/a6xx_gmu.c:645,1473` has inverted-check fix and CM3 halt. Not copied. |
| `qcom-pdc-wake-and-ss3.patch` | Already in v7.3. PDC passthrough/secondary support: `ad01c2b2f29163ca0bbe1fd4f9343fbc5119c239`; X1E register quirk: `e9a48ea4d90be251e0d057d41665745caccb0351`; domain_ss3: `95f827ceb21e2885f40eec5d93a340abbcc22d13`. `drivers/irqchip/qcom-pdc.c:255,513,717,722`, `hamoa.dtsi:308,310,473`. Entire supplied patch detects as already applied. |
| `serial-qcom-geni-force-suspend-resume.patch` | Already in v7.3, `d0cd9c8d0fd59bc7d140f3d60cf02e1d80376dab`; `drivers/tty/serial/qcom_geni_serial.c:2115,2126`. Not copied. |
| `soundwire-qcom-wait-for-irq-thread-before-gating-clock.patch` | Missing in v7.3 and vendor series. Included, before hclk gating in `swrm_runtime_suspend()`, supplied hunk moves from 1887 to 1813. Needed companion for restoring LPASS power management, but not proof every audio regression is fixed. |
| `scmi-qcom-memlat-rfc-v7.patch` | Optional memory bandwidth feature, not a CXSD prerequisite (upstream README:82). Not included. |
| `lpass-macro-release-votes-in-runtime-suspend.patch` | v7.3 contains TX `b9b23e72abef91ab4689f1467cefc2517042ab26` and RX `b05482e7ce1b110f86b08a99768ac41e4c9e4dfa`, BUT our vendor patches 0601–0604 undo PM clocks on WSA/RX/TX/VA and keep macro/dcodec votes alive. Instead of applying the older TX/RX-only patch, `lpass-restore-v7.3-pm-clocks.patch` restores all four files byte-for-byte to pristine v7.3. See original `lpass-{tx,rx,wsa,va}-macro.c:2335,3885,2791,1628` for `of_pm_clk_add_clks()`. Audio must be tested: the vendor reverts were specifically added for lost speakers after runtime PM. |
| `dts-vivobook-s15-edp-regulator-not-always-on.patch` | Still absent in v7.3; intentionally outside this module. Use the separately prepared panelPowerOff option. |
| `pmdomain-system-sleep-only.patch` | Missing. Included with SS1 DT patch; prevents the reported post-s2idle runtime-DRIPS hang. Not EL2-specific: generic genpd governor / state parsing / binding change. EL1 impact has not been tested on this machine. |
| `dts-hamoa-add-ss1-idle-state.patch` | Missing. Included: SS1 0x02000154 for runtime idle, SS3 0x0200c354 system-sleep-only. Needs preceding genpd patch. |
| `syscon-skip-clock-of-clock-providers.patch` | Missing (`drivers/mfd/syscon.c:126` still calls `of_clk_get` unconditionally). Included to remove the TCSR parent XO vote. This is a broad syscon workaround, not an upstream-reviewed fix. CXSD-only itself does not require XO shutdown. |
| `pcie-qcom-keep-gen1-icc-vote.patch` | Missing. Copied, opt-in only via pcieGen1Vote. Primarily link-up idle power, not a substitute for suspending PCIe roots. Under-votes bandwidth; DMA throughput may regress. |
| `vivobook-s15-ec-hid.patch` | Do not stack this alternative EC/HID implementation. Our vendor series supplies HID 0300 and EC 0401–0411; `qcom_hamoa_ec` is live, with allow_suspend=1 configured. The implementations are not identical; this is coverage by our existing driver, not an assertion that their patch is upstream. |
| `ec-timed-standby-experiment.patch` | Not applicable to our different EC driver, and source README:144–148 says unproven. Not included. |
| `x1-dc-zva-erratum-and-cl5.patch` | Experimental, not included. v7.3 already enables CL5 on all three clusters (`hamoa.dtsi:455,461,467`), but `arch/arm64/kernel/cpu_errata.c` has only the Oryon CNTVOFF workaround, no Broken DC ZVA workaround. This combined old patch cannot be blindly applied: its CL5 hunks are already present. Whether our EL1 firmware needs the DC ZVA part remains unknown; do not call it fixed. |
| `el1tmr` | Not applicable to normal EL1. Its init explicitly rejects !is_kernel_in_hyp_mode(); accesses EL02 timer aliases for VHE. Not included. |
| `aoss-cxsd-only` | Included and loaded by default when enabled. `qmp_send` is exported at `drivers/soc/qcom/qcom_aoss.c:278`; driver data is set at :622. A sleep.target prerequisite retries modprobe and fails sleep if it cannot load, instead of silently allowing AOSD. Unloading this module re-enables AOSD. |
| `adsp-pwr-lmts` | Included by default. Live EL1 system exposes `6800000.remoteproc:glink-edge.APPS_ADSP_PWR_LMTS_GLINK_PORT.-1.-1`; no EL2 dependency. Sends state 1/0 around suspend/resume. Actual timer reduction on our firmware remains unmeasured. |
| `adsp-sleepstate` | Copied, opt-in only with its SMP2P DT overlay. No EL2 dependency, but source README:194–197 calls necessity unresolved; source comment calls polarity inferred/untested. |

## Other settings from their NixOS module

- Included: disable unused clocks/domains, qcrypto blacklist plus
  `fw_devlink.sync_state=timeout`, `pcie_port_pm=force`, s2idle selection,
  USB runtime-PM allow rules.
- Not copied: their Micron `nvme.quirks=1344:5413:simple_suspend`. Our live
  controller is Samsung `144d:a80d`, so that identifier is wrong here. Whether
  this Samsung needs simple_suspend remains to be measured; check controller
  and root-port suspend status if DDR/CXSD counters still stay zero.
- Not copied: EL2 CPU overrides, EFI noruntime workaround, initrd module
  grab-bag, PSR/debug/ramoops settings, memlat devfreq polling rules.
- Not copied: USB LDO2/LDO3 always-on experiment. It compensates for disabling
  USB wakeup; this module does not disable USB wakeup.
- Their lid-open spurious-wakeup hook and sleep-energy logger are optional
  observability/wakeup behavior, not CX vote fixes; not included.

## Verification performed

- Downloaded 7.3 from kernel.org and checked SHA256 in the same Nix base32
  representation as kernel.nix:
  `0ls902gz6h1ydcnwx2zzdcglg52f14hmaxk2ncg341hfy4j3qdl7`.
- Applied the complete vendor series in its declared order, then all five
  default sleep patches plus the optional PCIe patch, with `patch --fuzz=0`.
  No failed hunks; only line offsets on SoundWire, hamoa and PCIe.
- Confirmed restored LPASS files match pristine v7.3 byte-for-byte.
- Evaluated from the secret flake using `--override-input nix-kyaru
  path:/home/kyaru/Projects/nix --no-write-lock-file` and an `extendModules`
  expression importing sleep.nix. Enabled kernel drvPath and the two default
  module drvPaths evaluate; actual kernel.patches contains the vendor series
  followed by the five sleep patches. All optional settings also evaluate,
  including the third module and overlay. No failed NixOS assertions.
- Compiled the optional sleepstate overlay standalone with `dtc -@`; no
  errors. Its filter is a literal DTB basename because the pinned nixpkgs
  apply_overlays.py uses substring matching, despite the option's glob wording.
- Importing the module without enabling it preserves the original kernel
  drvPath. `nixfmt` and `nix-instantiate --parse` pass.

`boot.kernelPatches` alone does not work with this host's kernel.nix: that
function overwrites the incoming list with the vendor series. This module
uses the existing final `argsOverride.kernelPatches` hook to append the
actual NixOS patch list after the vendor series, without editing kernel.nix.

Not verified: C compilation of the out-of-tree modules, audio after clock
collapse, successful suspend/resume, counters or battery drain. None of these
can be inferred from a Nix evaluation or a patch application test.
