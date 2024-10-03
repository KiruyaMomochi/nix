{ config, pkgs, lib, ... }:
let
  inherit (lib.modules) mkDefault mkMerge mkIf;
  inherit (lib.options) mkOption mkEnableOption;
in
{
  options = {
    kyaru.vps.enable = mkEnableOption "Enablt the VPS config";
    kyaru.vps.user.enable = mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable the VPS user, the default name is kyaru";
    };
    kyaru.vps.user.name = mkOption {
      type = lib.types.str;
      default = "kyaru";
      description = "Username";
    };
  };

  config = mkIf config.kyaru.vps.enable (mkMerge [
    {
      # Use the GRUB 2 boot loader.
      boot.loader.grub.enable = mkDefault true;

      # Enable TCP BBR
      boot.kernelModules = [ "tcp_bbr" ];
      boot.kernel.sysctl = {
        "net.core.default_qdisc" = "fq";
        "net.ipv4.tcp_congestion_control" = "bbr";
      };

      networking.nameservers = [
        "1.1.1.1#cloudflare-dns.com"
        "2606:4700:4700::1111#cloudflare-dns.com"
        "2606:4700:4700::1001#cloudflare-dns.com"
      ];

      systemd.network.enable = true;
      networking.useNetworkd = true;
      systemd.network.wait-online.anyInterface = true;
      systemd.network.networks."99-ethernet-default-dhcp".linkConfig.RequiredFamilyForOnline = "ipv4";

      nix.settings.auto-optimise-store = mkDefault true;

      # Telegraf
      services.telegraf.enable = mkDefault true;

      # Open ports in the firewall.
      networking.firewall.allowedTCPPorts = [ 22 80 443 ];
      networking.firewall.allowedUDPPorts = [ 443 ];
    }
    (
      let
        username = config.kyaru.vps.user.name;
      in
      mkIf config.kyaru.vps.user.enable {
        users.users.${username} = {
          isNormalUser = true;
          extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
          packages = [ ];
          shell = pkgs.fish;
          openssh.authorizedKeys.keys = [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/bxk6wXA396kICPAsNnnXqPt0zmUZgmDQZnem+0NDCmuMqCPn4+VBgMHaLWdrwLy3ct3D9j5DKrLZuhNWD73EkwnhdIqE8g2TAt+4KHVS6ppqH6hY6A51vevl8AZC3kIPFEvBMLdzh649cgv8qLoGEfa0Xu8YVmXOuQumaCO4sSj9+RWid1szJfM10uTeI6bGwDQCjwwA1wjBXX+S8pAg8seEL+naxDDYMp715im6mFG4c7Ti8cgZuEP5VqxjrumkBGkbia8yduhsvIK24BT6sW2vuXjYN4cvrVbHpw6hXLVvZLwNAkw9mTSiKEChnQj1JXCn80JxUKMSNKDmN0JZ"
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDW/IJAwHjPjTdy1Iv21ZV0Am9ElaNL4DfsFgrMhLQtRT3NL4sEF/FzZJfxN0my2dZqIx5kN6uUQb7+0emJg700XdljY3W70iMTLCXni4PtU+nME+5SNSbDi7mev9AbiCbTa+vDfa0be4WYPlPENl2NISvUzWUUbREDuLztnazkqRJ+JKo+Hcjru7f1dI1X10GCeA5lgpPZ4l1SjAXrRTku6mVLAj4YgaHwXfHUuwBPIYTw4zFArwonC4/8XGVItUR1bfs6cYI2ilbtFRQ1TqBYO+3XeSOMv53Eu6qpkxRcFo1oIaH9hY9r3wpe1l1h2OMsKKJwxPSU7XBDvFLxPJRvBwg9xcP7xCnuBMpuSwN+F+LbAqufobEAkdFh/FSMoOsxHxy/um8apfdGCYoMk6WWQViFaMpZOv/7WFpjOhGh4ftqHWLH9b/9rWnvu8PFCDelIUwgjNwQNvQI2DB1mOpiYzNYrTTPSYS2ShItsJke5j9KP5h9mR7u0MCdT8evpL0= kyaru@gourmet"
          ];
        };
        nix.settings.trusted-users = [ username ];
      }
    )
  ]);
}
