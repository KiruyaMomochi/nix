{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.fish;
in
{
  options.programs.kyaru.fish = {
    plugins.tide = with lib; {
      enable = mkEnableOption "Enable the tide plugin";
    };
  };

  config = lib.mkIf cfg.plugins.tide.enable {
    programs.fish.plugins = [
      rec {
        name = "tide";
        src = pkgs.fetchFromGitHub {
          owner = "IlanCosman";
          repo = name;
          rev = "v6.1.1";
          sha256 = "sha256-ZyEk/WoxdX5Fr2kXRERQS1U1QHH3oVSyBQvlwYnEYyc=";
        };
      }
    ];
  };
}
