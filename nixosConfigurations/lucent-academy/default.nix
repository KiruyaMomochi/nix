{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./vivobook.nix
    ./boot.nix
    ./face-unlock.nix
  ];

  # Fan control via the EC. Read vivobook-s15-fedora docs/ec-fan-control.md first.
  hardware.vivobook-s15.experimentalEC = true;

  kyaru.enable = true;
  kyaru.desktop.enable = true;
  kyaru.desktop.hyprland.enable = true;

  # Built-in numpad. The Wayland greeter is KWin, which ignores sddm.conf's
  # Numlock and reads kcminputrc from sddm's home instead (NumLock=0 means on).
  services.displayManager.sddm.autoNumlock = true;
  systemd.tmpfiles.settings."10-sddm-numlock" = {
    "/var/lib/sddm/.config".d = {
      user = "sddm";
      group = "sddm";
      mode = "0755";
    };
    "/var/lib/sddm/.config/kcminputrc"."L+".argument = "${pkgs.writeText "sddm-kcminputrc" ''
      [Keyboard]
      NumLock=0
    ''}";
  };

  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;

  users.users.kyaru.uid = 1000;
  users.users.kyaru.extraGroups = [ "video" "audio" ];
  users.users.kyaru.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHt7EEGFGu0Yg/XlowRZugaAWaHtdwOwx52VH6/5Yzn9 kyaru@caon"
  ];

  time.timeZone = "Asia/Taipei";
  environment.systemPackages = with pkgs; [ nushell ];
  programs.kdeconnect.enable = true;
  virtualisation.waydroid.enable = true;

  system.stateVersion = "26.05";
}
