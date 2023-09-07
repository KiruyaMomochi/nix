{ config, lib, pkgs, ... }:
let
  cfg = config.programs.kyaru.spack;
in
{
  options.programs.kyaru.spack = {
    enable = lib.mkEnableOption "Kiruya's spack packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      gcc
      cmake
      perl
      patchelf
      gnumake
      gnupg
      automake
      autoconf
      pkgconf
      openmpi
      szip
      zlib
      jdk
    ];
  };
}
