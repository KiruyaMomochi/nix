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
  };

  config = {
    boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./kernel.nix { inherit src; });

    hardware.deviceTree = {
      enable = true;
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

    boot.kernelParams = [
      "pd_ignore_unused"
      "clk_ignore_unused"
      # Firmware advertises the Qualcomm fTPM but Linux has no driver for it yet, so
      # systemd-tpm2-generator would wait 2x45s for /dev/tpmrm0. Drop once a driver lands.
      "systemd.tpm2_wait=0"
    ];
  };
}
