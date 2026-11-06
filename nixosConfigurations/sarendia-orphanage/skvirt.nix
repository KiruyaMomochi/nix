{ pkgs, ... }:
let
  # skvirt writes /dev/uinput and reads touch/pointer devices to tell a
  # finger from the mouse. logind gives the active seat user ACLs on these;
  # keyboard nodes (including mixed keyboard/pointer and hotkey ones) are
  # left out. Has to sort before 73-seat-late.rules, where uaccess is applied,
  # and after 60-input-id.rules, which sets ID_INPUT_*.
  inputAccess = pkgs.writeTextDir "lib/udev/rules.d/72-skvirt-uaccess.rules" ''
    ACTION=="remove", GOTO="skvirt_end"
    SUBSYSTEM=="misc", KERNEL=="uinput", TAG+="uaccess"
    SUBSYSTEM!="input", GOTO="skvirt_end"
    KERNEL!="event*", GOTO="skvirt_end"
    ENV{ID_INPUT_KEYBOARD}=="1", GOTO="skvirt_end"
    ENV{ID_INPUT_KEY}=="1", GOTO="skvirt_end"
    ENV{ID_INPUT_TOUCHSCREEN}=="1", TAG+="uaccess"
    ENV{ID_INPUT_TABLET}=="1", TAG+="uaccess"
    ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"
    ENV{ID_INPUT_TOUCHPAD}=="1", TAG+="uaccess"
    ENV{ID_INPUT_POINTINGSTICK}=="1", TAG+="uaccess"
    ENV{ID_INPUT_SWITCH}=="1", TAG+="uaccess"
    LABEL="skvirt_end"
  '';
in
{
  services.udev.packages = [ inputAccess ];
  boot.kernelModules = [ "uinput" ];
  environment.systemPackages = [ pkgs.kyaru.skvirt ];
  # D-Bus activates the lock screen watcher (org.skvirt.KWinLauncher).
  services.dbus.packages = [ pkgs.kyaru.skvirt ];

  # Plasma only: it talks to KWin's virtual keyboard D-Bus API.
  environment.etc."xdg/autostart/skvirt.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=skvirt
    Exec=skvirt
    OnlyShowIn=KDE;
    NoDisplay=true
  '';

  # KWin's input method (System Settings > Keyboard > Virtual Keyboard) is
  # "skvirt (desktop and lock screen)"; fcitx5-osk stays installed until
  # that has been used on the real lock screen.
}
