{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
{
  users.users.yozakura = {
    isNormalUser = true;
    uid = 1002;
    description = "Yozakura";
    createHome = true;
    shell = pkgs.nushell;
    extraGroups = [
      "wheel"
      "networkmanager"
    ]
    ++ optionals config.programs.wireshark.enable [ "wireshark" ]
    ++ optionals config.virtualisation.docker.enable [ "docker" ]
    ++ optionals config.virtualisation.podman.enable [ "podman" ]
    ++ optionals config.virtualisation.libvirtd.enable [ "libvirtd" ]
    ++ optionals config.hardware.sane.enable [
      "scanner"
      "lp"
    ]
    ++ optionals config.hardware.i2c.enable [ "i2c" ];
  };

  nix.settings.trusted-users = [ "yozakura" ];
}
