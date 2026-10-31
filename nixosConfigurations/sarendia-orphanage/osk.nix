{ pkgs, ... }:
let
  osk = pkgs.kyaru.fcitx5-osk;
in
{
  # On-screen keyboard that types through fcitx5, for tablet mode.
  # Pick "Fcitx 5 Osk Kwin Launcher" in System Settings > Keyboard >
  # Virtual Keyboard (it replaces the plain Fcitx 5 entry there).
  # The KWin effect pops the keyboard when a finger taps a text field
  # (mouse clicks don't count, so ignore_fcitx_show can stay on).
  environment.systemPackages = [ osk pkgs.kyaru.fcitx5-osk-kwin-effect ];
  services.dbus.packages = [ osk ];

  # Root helper that presses Ctrl/Shift/Alt through uinput, working around
  # fcitx5's Wayland frontend not forwarding modifiers.
  systemd.packages = [ osk ];
  systemd.services.fcitx5-osk-key-helper.wantedBy = [ "multi-user.target" ];
  boot.kernelModules = [ "uinput" ];
}
