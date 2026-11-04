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

  # The greeter's own Hyprland: built-in numpad on, same scale and cursor as the session
  # (homeConfigurations "kyaru@lucent-academy"). Replaces the greeter's default config,
  # so its two lines are repeated here.
  services.displayManager.dux-greeter.compositor.customConfig = ''
    hl.env("DMS_RUN_GREETER", "1")
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.25 })
    hl.config({
      misc = { disable_hyprland_logo = true },
      input = { numlock_by_default = true, touchpad = { natural_scroll = true } },
      cursor = { no_hardware_cursors = true },
    })
  '';

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
