# EL2 CXSD experiment

This is an opt-in kernel/DT specialisation, **not** a boot installer. No EFI
files are written by these derivations. `boot.nix`, the installer and the EFI
launcher are separate integration work. Never boot its UKI directly without
qebspil + slbounce and a known-working Microsoft-signed tcblaunch payload.

## Contract

`specialisation.el2-cxsd` enables the same deepSleep options as `cxsd`:
LPASS PM clocks, SoundWire fix, SS1 runtime / SS3 system sleep, syscon fix,
PCIe diagnostics, ADSP Modern Standby and `aoss_cxsd_only`. Panel always-on
is removed; ignore-unused is off. No el1tmr module is added. Command line
adds `id_aa64mmfr1.vh=0 id_aa64mmfr0.ecv=1 efi=noruntime` (nVHE).
EFI variables cannot be used from this entry. Do not run guests during
initial suspend testing.

The kernel's upstream `qcom/x1e80100-asus-vivobook-s15-el2.dtb` supplies
GPU zap disabled, PCIe SMMUv3 + maps, native watchdog and disabled IRIS.
In `vivobook.nix`, the existing name-relative dtbSource/panel edit pipeline
also edits this EL2 DTB: remove ADSP/CDSP `iommus`, add `qcom,broken-reset`
and set SCM `qcom,shm-bridge-vmid = <0xffffffff>` (SELF_OWNER).
This deliberately follows qebspil's firmware-owned DSP mapping contract,
**not** upstream's Linux-managed DSP IOMMU path. Symbol-based fdtget probes
and status assertions fail the build if expected nodes/properties are absent.
The BurninChrome audio/EC overlay has no filename filter and still applies
to the renamed DTB. The disabled, optional ADSP sleepstate overlay is not
part of this configuration.

## Patch provenance and port details

- `remoteproc-qebspil-attach-v7.3.patch`: derived from Stephan Gerhold's
  [a05245a0d9c218f72dcbb28448c426cdc455bce3](https://github.com/jglathe/linux_ms_dev_kit/commit/a05245a0d9c218f72dcbb28448c426cdc455bce3)
  and the running-state predicate used by
  [5e9f7759aa2295ece046a03d48cee341affde404](https://github.com/jglathe/linux_ms_dev_kit/commit/5e9f7759aa2295ece046a03d48cee341affde404),
  as carried at jglathe/linux_ms_dev_kit `0aaff8f`.
  v7.3 already has detached auto-attach and qcom_pas_attach, so no changes
  to remoteproc core, other drivers, or the boolean auto_boot API are needed.
  Only broken-reset DSPs use the ready+handover+!fatal+!stop SMP2P predicate;
  unreadable incoming entries defer probing rather than assume OFFLINE.
  There are no load/start ops. Unlike the WIP original, stop returns
  EOPNOTSUPP without PAS shutdown/unprepare; recovery is disabled. **A DSP
  crash or a desire to stop it requires reboot, not a sysfs restart.** Do
  not unbind/unload the DSP driver as a recovery method. Other remoteprocs
  keep v7.3 behavior.
- `qcom-tzmem-self-owner-v7.3.patch`: selective port of `qcom_tzmem.c` and
  the SCM binding constant from
  [jglathe/linux_ms_dev_kit at 0aaff8f](https://github.com/jglathe/linux_ms_dev_kit/tree/0aaff8f).
  v7.3 does **not** interpret the DT property above without this patch.
  Keep v7.3's DO_ONCE init and allocator updates; import only VMID selection,
  SELF_OWNER flags/permissions and its binding constant. Absent the property,
  HLOS remains the default. Current configuration uses SHMBRIDGE mode.
- `arm-arch-timer-park-stopped.patch`: Anthony Ruhier's
  [gist revision 2b2a6b3f8f80e8702f4b78d6c790f6853716d9e4](https://gist.github.com/aruhier/08932aea5eb29e3fca832b3c8b471bf7/2b2a6b3f8f80e8702f4b78d6c790f6853716d9e4),
  file raw revision `f65d93d494685bfb2803f9fa0274b3dfeed5d858`.
  Unchanged logic; v7.3 applies with a four-line offset. CVAL parks at
  `BIT(arch_counter_get_width() - 1) - 1`, enabled and masked.
- `qebspil-qmp.patch`: unmodified
  [justririll/x1e-sleep 4e84b60eb073e76f8f7190a168c90c0d869b1326](https://github.com/justririll/x1e-sleep/blob/4e84b60eb073e76f8f7190a168c90c0d869b1326/qebspil/0001-pil-send-AOSS-load_state-off-on-before-starting-ADSP.patch).
  Base is **stephan-gh/qebspil 8e4d9e676a3b3afe136cda9b953a2139ff1a32d0**,
  not TravMurav's different tree. Pins both gitlink revisions (gnu-efi/dtc)
  separately by hash. `QEBSPIL_ALWAYS_START=0` remains set. QMP failures
  are upstream's nonfatal behavior; boot success alone does not validate QMP.
- slbounce uses upstream **v5 release binaries**, not an unpinned source
  build. Both driver and sltest have fixed hashes; neither is signed by this
  derivation. The driver retains upstream's DT-based EL2 guard.

## Build outputs / installation boundary

From the **secret** flake with the public path input overridden:

```
nix build --impure --no-link --print-out-paths \
  --override-input nix-kyaru path:/home/kyaru/Projects/nix --no-write-lock-file \
  .#nixosConfigurations.lucent-academy.config.specialisation.el2-cxsd.configuration.system.build.toplevel
```

The specialisation exports `system.build.el2-qebspil` and
`system.build.el2-slbounce`, also retained through `system.extraDependencies`.
Their files are `share/efi/qebspilaa64.efi`, `share/efi/slbounceaa64.efi` and
`share/efi/sltestaa64.efi`. The final toplevel's `lucent-dtb-name` should be
`qcom/x1e80100-asus-vivobook-s15-el2.dtb`.

The integrator must separately supply tcblaunch and the four private ASUS DSP
blobs on the **driver's filesystem**, then sign drivers/launcher/UKI. No
Microsoft/OEM blobs or signing keys belong in this public tree. No global
systemd-boot drivers are installed here. IRIS hardware video decode is
intentionally lost in the initial upstream EL2 setup.

Build success is not a runtime result. Verify the **final** DT after all
overlays: both broken-reset DSPs without iommus, correct firmware-name,
SCM SELF_OWNER, zap disabled, PCIe SMMU okay, SBSA watchdog disabled,
IRIS disabled, panel not always-on, plus audio/EC nodes. Then verify EL2 boot,
DSP attach, battery/audio/USB-C and short CXSD+DDR sleep while retaining
the AOSD inhibitor. BIOS .368 and the stricter attach-only port remain
unverified until tested on hardware.
