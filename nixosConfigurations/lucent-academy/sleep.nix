{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hardware.vivobook-s15.deepSleep;
  src = inputs.vivobook-s15-fedora;
  series = lib.filter (l: l != "" && !lib.hasPrefix "#" l) (
    lib.splitString "\n" (builtins.readFile "${src}/kernel/patches/series")
  );
  vendorPatches = map (name: {
    inherit name;
    patch = "${src}/kernel/patches/${name}";
  }) series;
  patch = name: {
    inherit name;
    patch = ./sleep + "/${name}.patch";
  };
  kernel = config.boot.kernelPackages.kernel;
  mkModule =
    dir: module:
    pkgs.stdenv.mkDerivation {
      pname = dir;
      version = "0-unstable-2026-10-10";
      src = ./sleep + "/${dir}";
      nativeBuildInputs = kernel.moduleBuildDependencies;
      hardeningDisable = [ "pic" ];
      buildPhase = ''
        runHook preBuild
        make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -Dm444 ${module}.ko $out/lib/modules/${kernel.modDirVersion}/extra/${module}.ko
        runHook postInstall
      '';
      meta.platforms = [ "aarch64-linux" ];
    };
in
{
  options.hardware.vivobook-s15.deepSleep = {
    enable = lib.mkEnableOption "experimental CXSD s2idle support (EL1; keeps AOSD disabled)";
    adspPowerLimits = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Send Modern Standby notifications on the ADSP power-limits rpmsg channel.";
    };
    adspSleepstate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Experimental ADSP SMP2P sleepstate notification; necessity and polarity remain unverified.";
    };
    pcieGen1Vote = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Cap PCIe bandwidth votes at Gen1 x1. May hurt DMA throughput; not needed when root ports suspend.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.vivobook-s15.ignoreUnused = lib.mkDefault false;
    assertions = [
      {
        assertion = !config.hardware.vivobook-s15.ignoreUnused;
        message = "deepSleep requires hardware.vivobook-s15.ignoreUnused = false.";
      }
    ];

    # kernel.nix replaces its kernelPatches argument, so boot.kernelPatches alone
    # silently does nothing. Pass the complete list through its final argsOverride.
    boot.kernelPackages = lib.mkForce (
      pkgs.linuxPackagesFor (
        pkgs.callPackage ./kernel.nix {
          inherit src;
          argsOverride.kernelPatches = vendorPatches ++ config.boot.kernelPatches;
        }
      )
    );
    boot.kernelPatches = map patch (
      [
        "lpass-restore-v7.3-pm-clocks"
        "soundwire-qcom-wait-for-irq-thread-before-gating-clock"
        "syscon-skip-clock-of-clock-providers"
        "pmdomain-system-sleep-only"
        "dts-hamoa-add-ss1-idle-state"
      ]
      ++ lib.optional cfg.pcieGen1Vote "pcie-qcom-keep-gen1-icc-vote"
    );

    boot.extraModulePackages = [
      (mkModule "aoss-cxsd-only" "aoss_cxsd_only")
    ]
    ++ lib.optional cfg.adspPowerLimits (mkModule "adsp-pwr-lmts" "qcom_adsp_pwr_lmts")
    ++ lib.optional cfg.adspSleepstate (mkModule "adsp-sleepstate" "asus_adsp_sleepstate");
    boot.kernelModules = [
      "aoss_cxsd_only"
    ]
    ++ lib.optional cfg.adspPowerLimits "qcom_adsp_pwr_lmts"
    ++ lib.optional cfg.adspSleepstate "asus_adsp_sleepstate";

    # QCE's DDR vote is unnecessary with ARMv8 CE. Unprobed devices must not
    # prevent interconnect providers from dropping their boot-time votes.
    boot.blacklistedKernelModules = [ "qcrypto" ];
    boot.kernelParams = [
      "fw_devlink.sync_state=timeout"
      "pcie_port_pm=force"
      "mem_sleep_default=s2idle"
    ];
    systemd.sleep.settings.Sleep.MemorySleepMode = "s2idle";
    services.udev.extraRules = ''
      ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="dwc3-qcom|xhci-hcd|qcom-qmp-combo-phy|qcom-qmp-usb-phy", ATTR{power/control}="auto"
    '';

    # A failed stage-2 modprobe must not silently allow an AOSD sleep. Retry
    # immediately before sleep, and fail the sleep transaction if it fails.
    systemd.services.vivobook-cxsd-only = {
      description = "Inhibit AOSD before system sleep";
      requiredBy = [ "sleep.target" ];
      before = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.kmod}/bin/modprobe aoss_cxsd_only";
      };
    };

    hardware.deviceTree.overlays = lib.optional cfg.adspSleepstate {
      name = "vivobook-adsp-sleepstate";
      # The pinned apply_overlays.py treats this as a substring, not a glob.
      filter = "x1e80100-asus-vivobook-s15.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;
        / { compatible = "asus,vivobook-s15"; };
        &{/smp2p-adsp} {
          sleepstate_smp2p_out: sleepstate-out {
            qcom,entry-name = "sleepstate";
            #qcom,smem-state-cells = <1>;
          };
        };
        &{/} {
          adsp-sleepstate {
            compatible = "asus,adsp-sleepstate";
            qcom,smem-states = <&sleepstate_smp2p_out 0>;
            qcom,smem-state-names = "sleepstate";
          };
        };
      '';
    };
  };
}
