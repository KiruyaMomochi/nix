{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.vivobook-s15.el2;
  patch = name: {
    inherit name;
    patch = ./el2-support + "/${name}.patch";
  };
in
{
  options.hardware.vivobook-s15.el2.enable =
    lib.mkEnableOption "experimental qebspil/slbounce EL2 boot (requires an entry-scoped EFI launcher)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          config.hardware.vivobook-s15.deepSleep.enable && !config.hardware.vivobook-s15.disableAdsp;
        message = "EL2 bring-up requires the CXSD baseline with ADSP enabled.";
      }
    ];
    hardware.deviceTree.name = lib.mkForce "qcom/x1e80100-asus-vivobook-s15-el2.dtb";
    # sleep.nix passes boot.kernelPatches through kernel.nix's argsOverride.
    boot.kernelPatches = map patch [
      "remoteproc-qebspil-attach-v7.3"
      "remoteproc-qebspil-state-window-v7.3"
      "smp2p-qebspil-handover-v7.3"
      "qcom-tzmem-self-owner-v7.3"
      "arm-arch-timer-park-stopped"
    ];
    boot.kernelParams = [
      "id_aa64mmfr1.vh=0"
      "id_aa64mmfr0.ecv=1"
      # Follow the known-good bring-up configuration. EFI variables unavailable
      # in this entry: select the next entry from EL1, not from EL2.
      "efi=noruntime"
      # Experiment 11-13: ADSP started by qebspil is dead by the time PAS probes.
      # Let unmatched streams (ADSP 0x1000 has no iommus here) bypass the apps SMMU.
      "arm_smmu.disable_bypass=0"
      # Experiment 11-13: ADSP never reaches ready (no crash). Keep UEFI-enabled
      # clocks/PDs alive until the PAS driver probes.
      "clk_ignore_unused"
      "pd_ignore_unused"
    ];
    # Outputs only, never installs on the ESP. The boot-chain integrator signs
    # these drivers and supplies tcblaunch + the private DSP firmware separately.
    system.build.el2-qebspil = pkgs.callPackage ./el2-support/qebspil.nix { };
    system.build.el2-slbounce = pkgs.callPackage ./el2-support/slbounce.nix { };
    system.build.el2-launcher = pkgs.callPackage ./el2/launcher.nix {
      # GPT PARTUUID of /boot (XBOOTLDR, nvme0n1p15).
      bootPartuuid = "5315940d-97e9-459d-a1fc-65f01540c47a";
      # install-bootloader.sh copies the newest el2 UKI here.
      ukiPath = "/EFI/nixos/lucent-el2.efi";
    };
    # install-bootloader.sh sees this directory and installs the EL2 entry on the ESP.
    system.systemBuilderCommands = ''
      mkdir $out/lucent-el2
      ln -s ${config.system.build.el2-launcher}/lib/efi/lucent-el2-launcher.efi $out/lucent-el2/launcher.efi
      ln -s ${config.system.build.el2-qebspil}/share/efi/qebspilaa64.efi $out/lucent-el2/qebspilaa64.efi
      ln -s ${config.system.build.el2-slbounce}/share/efi/slbounceaa64.efi $out/lucent-el2/slbounceaa64.efi
    '';
  };
}
