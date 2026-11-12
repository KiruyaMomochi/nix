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
      "qcom-tzmem-self-owner-v7.3"
      "arm-arch-timer-park-stopped"
    ];
    boot.kernelParams = [
      "id_aa64mmfr1.vh=0"
      "id_aa64mmfr0.ecv=1"
      # Follow the known-good bring-up configuration. EFI variables unavailable
      # in this entry: select the next entry from EL1, not from EL2.
      "efi=noruntime"
    ];
    # Outputs only, never installs on the ESP. The boot-chain integrator signs
    # these drivers and supplies tcblaunch + the private DSP firmware separately.
    system.build.el2-qebspil = pkgs.callPackage ./el2-support/qebspil.nix { };
    system.build.el2-slbounce = pkgs.callPackage ./el2-support/slbounce.nix { };
    system.extraDependencies = [
      config.system.build.el2-qebspil
      config.system.build.el2-slbounce
    ];
  };
}
