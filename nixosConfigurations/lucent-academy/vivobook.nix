{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

# ASUS Vivobook S 15 S5507QAD (Snapdragon X Elite, x1e80100).
# Kernel patches and DT overlay come from BurninChrome/vivobook-s15-fedora;
# initrd module list and kernel params follow kuruczgy/plxty x1e-nixos-config.
let
  cfg = config.hardware.vivobook-s15;
  src = inputs.vivobook-s15-fedora;
in
{
  options.hardware.vivobook-s15 = {
    firmware = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Directory laid out as lib/firmware (qcom/x1e80100/ASUSTeK/vivobook-s15/*).
      '';
    };
    experimentalEC = lib.mkEnableOption "the EC node (fan control via qcom-hamoa-ec). Read upstream docs/ec-fan-control.md first";
    panelPowerOff = lib.mkEnableOption ''
      dropping regulator-always-on from VREG_EDP_3P3 so the OLED panel loses
      power in s2idle (justririll/x1e-sleep measured ~1.2 W saved). An overlay
      can't delete a property, so the base dtb is edited with fdtput'';
    disableAdsp = lib.mkEnableOption ''
      ADSP status = "disabled" in the base dtb (Johan's CRD CXSD setup). Kills
      battmgr, audio and USB-C status; diagnostic boots only'';
    ignoreUnused = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass pd_ignore_unused/clk_ignore_unused so the kernel never powers off
        domains/clocks it thinks are unused. Early x1e boots needed this; with it
        on, unused GDSCs (ufs, usb phys, gpu) stay up in idle and suspend.
      '';
    };
  };

  config = {
    boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./kernel.nix { inherit src; });

    hardware.deviceTree = {
      enable = true;
      dtbSource = lib.mkIf (cfg.panelPowerOff || cfg.disableAdsp) (
        pkgs.runCommand "vivobook-s15-dtbs-edited"
          { nativeBuildInputs = [ pkgs.dtc ]; }
          (
            ''
              cp -r ${config.boot.kernelPackages.kernel}/dtbs $out
              chmod -R u+w $out
              f=$out/${config.hardware.deviceTree.name}
            ''
            + lib.optionalString cfg.panelPowerOff ''
              fdtget $f /regulator-edp-3p3 regulator-name
              fdtput -d $f /regulator-edp-3p3 regulator-always-on
            ''
            + lib.optionalString cfg.disableAdsp ''
              fdtget $f /soc@0/remoteproc@6800000 compatible
              fdtput -t s $f /soc@0/remoteproc@6800000 status disabled
            ''
          )
      );
      name = "qcom/x1e80100-asus-vivobook-s15.dtb";
      overlays = [
        {
          name = "vivobook-s15";
          dtboFile = "${
            pkgs.callPackage ./dtbo.nix {
              inherit src;
              fragmentDirs = [ "" ] ++ lib.optional cfg.experimentalEC "experimental";
            }
          }/vivobook-s15.dtbo";
        }
      ];
    };

    hardware.firmware = lib.optional (cfg.firmware != null) (
      pkgs.runCommand "vivobook-s15-firmware" { } ''
        mkdir -p $out/lib/firmware
        cp -r ${cfg.firmware}/. $out/lib/firmware/
      ''
    );
    hardware.enableRedistributableFirmware = true;

    boot.initrd.includeDefaultModules = false;
    # usb_storage, tcsrcc_x1e80100 and pcie_qcom are built in (=y) on this kernel.
    boot.initrd.availableKernelModules = [
      # USB
      "phy_qcom_qmp_combo"
      "phy_snps_eusb2"
      "phy_qcom_eusb2_repeater"
      "phy_nxp_ptn3222"
      "phy_qcom_qmp_usb"
      # keyboard/touchpad, display
      "i2c_hid_of"
      "i2c_qcom_geni"
      "dispcc-x1e80100"
      "gpucc-x1e80100"
      "phy_qcom_edp"
      "panel_edp"
      "panel_samsung_atna33xc20"
      "msm"
      # storage
      "nvme"
      "phy_qcom_qmp_pcie"
      "dm_mod"
    ];

    # With the EC driver fed, the EC hard-resets ~2 min after Tj reports stop.
    # allow_suspend makes the driver disarm that around sleep; upstream only tested s2idle.
    boot.extraModprobeConfig = lib.mkIf cfg.experimentalEC "options qcom_hamoa_ec allow_suspend=1";
    systemd.sleep.settings.Sleep.MemorySleepMode = lib.mkIf cfg.experimentalEC "s2idle";

    boot.kernelParams = lib.optionals cfg.ignoreUnused [
      "pd_ignore_unused"
      "clk_ignore_unused"
    ] ++ [
      # Firmware advertises the Qualcomm fTPM but Linux has no driver for it yet, so
      # systemd-tpm2-generator would wait 2x45s for /dev/tpmrm0. Drop once a driver lands.
      "systemd.tpm2_wait=0"
    ];
  };
}
