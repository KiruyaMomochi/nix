{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.starship;
  inherit (lib) types mkOption mkMerge;
in
{
  options.programs.kyaru.starship = {
    presets = mkOption {
      description = ''
        Starship presets, see https://starship.rs/presets/
      '';
      type = types.listOf types.str;
      default = [];
      example = [ "nerd-font-symbols" ];
    };
  };

  config = {
    programs.starship = {
      settings = mkMerge (builtins.map (preset: (builtins.fromTOML (builtins.readFile (./presets + "/${preset}.toml")))) cfg.presets);
    };
  };
}
