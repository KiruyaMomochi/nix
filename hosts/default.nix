{ inputs, config, pkgs, lib, ... }:
let
  inherit (lib.modules) mkDefault mkMerge;
  inherit (lib.lists) optional singleton;
  nixos-version-file = pkgs.writeText "nixos-version.json" (builtins.toJSON config.system.nixos);
in
{
  imports = [
    inputs.self.nixosModules.all
    inputs.sops-nix.nixosModules.sops
    # https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  boot.lanzaboote.pkiBundle = "/etc/secureboot";

  # Enable flakes
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" "repl-flake" ];
    substituters = [ "https://objects.kyaru.bond/nix-cache" ];
    trusted-public-keys = [ "kyaru-nix-cache-1:Zu6gS5WZt4Kyvi95kCmlKlSyk+fbIwvuuEjBmC929KM=" ];
  };
  nixpkgs.config = import ../nixpkgs-config.nix;

  boot.kernelModules = [
    "nft_tproxy"
    "nft_socket"
  ];

  # Use nftables backend
  networking.nftables.enable = true;
  networking.firewall.enable = true;
  # NixOS is now using iptables-nftables-compat even when using iptables, therefore Networkmanager now uses the nftables backend unconditionally.
  # networking.networkmanager.firewallBackend = "nftables";

  environment.systemPackages = with pkgs; [
    helix # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    bat
    fish
    git
    tmux
    htop
    wget
    curl
    nftables
  ] ++ (
    # For debugging and troubleshooting Secure Boot.
    optional config.boot.lanzaboote.enable pkgs.sbctl
  );

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.

  programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  programs.fish.enable = true;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.fail2ban.enable = true;

  # Nspawn
  systemd.services."container-getty@" = {
    environment = {
      TERM = "xterm-256color";
    };
  };

  # NetworkManager hangs
  systemd.services.NetworkManager-wait-online = {
    serviceConfig.ExecStart = [ "" "${pkgs.networkmanager}/bin/nm-online -q" ];
  };

  # ACME
  security.acme = {
    acceptTerms = true;
    # defaults.webroot = mkDefault "/var/lib/acme/acme-challenge";
  };

  # Telegraf
  services.telegraf = {
    extraConfig = mkMerge [
      (builtins.fromTOML (builtins.readFile ./telegraf.conf))
      {
        agent.interval = mkDefault "10s";
        agent.flush_interval = mkDefault "10s";
      }
      {
        inputs.net = mkDefault (singleton {
          interfaces = [ "eth*" "enp0s[0-1]" "lo" ];
        });
      }
      {
        inputs.exec = [
          {
            commands = singleton "${pkgs.coreutils}/bin/cat ${nixos-version-file}";
            data_format = "json_v2";
            timeout = "5s";
            flush_interval = "60s";
            json_v2 = singleton {
              measurement_name = "nixos";
              object = singleton {
                # https://github.com/tidwall/gjson/blob/master/SYNTAX.md#modifiers
                path = "@this";
                disable_prepend_keys = true;
                included_keys = [ "codeName" "release" "revision" "tags" "variant_id" "version" "versionSuffix" ];
                fields = {
                  release = "string";
                };
              };
            };
          }
        ];
      }
    ];
  };

  # from https://nixos-and-flakes.thiscute.world/best-practices/nix-path-and-flake-registry
  # make `nix run nixpkgs#nixpkgs` use the same nixpkgs as the one used by this flake.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # but NIX_PATH is still used by many useful tools, so we set it to the same value as the one used by this flake.
  # Make `nix repl '<nixpkgs>'` use the same nixpkgs as the one used by this flake.
  nixpkgs.flake.setNixPath = true;

  i18n.defaultLocale = mkDefault "en_US.UTF-8";

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # This option is not compactiable with flakes
  # system.copySystemConfiguration = true;
}
