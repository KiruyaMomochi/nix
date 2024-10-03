{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.gnome;
in
{
  options.programs.kyaru.gnome = with lib; {
    enable = mkEnableOption "Kiruya's gnome packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
    ];
  };
}
