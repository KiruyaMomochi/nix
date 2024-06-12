{ config, pkgs, lib, ... }:
with lib;
{
  options = {
    kyaru.networking = {
      enable = mkEnableOption (mdDoc "Enable networking for VPS");
      interface = mkOption {
        type = types.str;
        description = "Interface to use for networking";
        example = "eth0";
      };
      ipv4.addresses = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "IPv4 addresses to assign to the interface, with CIDR notation";
        example = [ "1.2.3.4/24" "5.6.7.8/24" ];
      };
      ipv4.gateway = mkOption {
        type = types.str;
        description = "IPv4 gateway to use";
        example = "1.2.3.1";
      };
      ipv6 = {
        addresses = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "IPv6 addresses to assign to the interface, with CIDR notation";
          example = [ "2001:db8::2/48" "2001:db8::3/48" ];
        };
        gateway = mkOption {
          type = types.str;
          description = "IPv6 gateway to use";
          example = "2001:db8::1";
        };
        gatewayOnLink = mkOption {
          type = types.bool;
          default = false;
          description = "Add an extra route to the IPv6 gateway, which is required for some providers. See https://serverfault.com/a/978385.";
        };
        acceptRA = mkOption {
          type = types.bool;
          default = true;
          description = "Accept IPv6 router advertisements. This is required for some providers. See https://serverfault.com/a/978385.";
        };
      };
    };
  };

  config =
    let
      splitCIDR = str:
        let
          parts = splitString "/" str;
          result = throwIfNot (builtins.length parts == 2) "Invalid CIDR notation" {
            address = builtins.elemAt parts 0;
            prefixLength = toInt (builtins.elemAt parts 1);
          };
        in
        result;
      cfg = config.kyaru.networking;
      static4 = (builtins.length cfg.ipv4.addresses) > 0;
      static6 = (builtins.length cfg.ipv6.addresses) > 0;
      dhcp =
        if static4 && static6 then "no"
        else if static4 then "ipv6"
        else if static6 then "ipv4"
        else "yes";
    in
    mkIf cfg.enable {
      systemd.network.networks."40-${cfg.interface}" = (mkMerge [
        {
          matchConfig.Name = "${cfg.interface}";
          networkConfig.IPv6PrivacyExtensions = "kernel";
          DHCP = dhcp;
          address = cfg.ipv4.addresses ++ cfg.ipv6.addresses;
          gateway = optional static4 cfg.ipv4.gateway;
          networkConfig.IPv6AcceptRA = cfg.ipv6.acceptRA;
        }
        (mkIf static6 {
          routes = [{
            Gateway = cfg.ipv6.gateway;
            GatewayOnLink = cfg.ipv6.gatewayOnLink;
          }];
        })
      ]);
    };
}
