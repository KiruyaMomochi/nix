{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.programs.lmod;
in
{
  options.programs.lmod = {
    enable = mkEnableOption "Lmod: An Environment Module System based on Lua, Reads TCL Modules, Supports a Software Hierarchy";
    package = mkPackageOption pkgs "lmod" { };

    enableBashIntegration = mkEnableOption "Bash integration" // {
      default = true;
    };

    enableZshIntegration = mkEnableOption "Zsh integration" // {
      default = true;
    };

    enableFishIntegration = mkEnableOption "Fish integration" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    programs.bash.initExtra = mkIf cfg.enableBashIntegration ''
      source ${cfg.package}/lmod/lmod/init/profile
    '';
    programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
      source ${cfg.package}/lmod/lmod/init/profile
    '';
    programs.fish.interactiveShellInit = mkIf cfg.enableFishIntegration ''
      source ${cfg.package}/lmod/lmod/init/profile.fish
    '';
  };
}
