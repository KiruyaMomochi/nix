{ pkgs, ... }:
{
  # The on-screen keyboard lives inside fcitx, so KWin's one input method
  # slot stays "Fcitx 5" and it works on the desktop and the lock screen
  # alike.
  i18n.inputMethod.fcitx5.addons = [ pkgs.kyaru.fcitx5-hotaru ];
}
