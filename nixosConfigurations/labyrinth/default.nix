{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./attic.nix
  ];

  kyaru.enable = true;
  kyaru.vps.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Asia/Singapore";

  services.hedgedoc = {
    enable = true;
  };

  zramSwap.enable = true;
  virtualisation.oci-containers.containers = {
    grist = {
      image = "gristlabs/grist:latest";
      pull = "newer";
      ports = [ "127.0.0.1:8484:8484" ];
      volumes = [ "grist:/persist" ];
      environment = {
        TZ = "Asia/Shanghai";
      };
    };
  };
  services.sftpgo = {
    enable = true;
    extraReadWriteDirs = [
      "/mnt/data/share"
      "/mnt/data/users"
    ];
    settings = {
      httpd.bindings = [
        {
          port = 9443;
          address = "127.0.0.1";
          enable_web_admin = true;
          enable_web_client = true;
          oidc = {
            scopes = [
              "openid"
              "profile"
              "email"
            ];
            username_field = "upn";
            role_field = "sftpgo_role";
            implicit_roles = true;
          };
        }
      ];
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
