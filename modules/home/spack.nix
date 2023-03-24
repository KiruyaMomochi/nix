{ config, pkgs, ... }:

{
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
}
