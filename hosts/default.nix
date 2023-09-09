{ inputs, config, pkgs, lib, ... }:
let
  inherit (lib.modules) mkDefault;
  inherit (lib.lists) optional;
in
{
  imports = [
    inputs.self.nixosModules.all
    inputs.sops-nix.nixosModules.sops
    # https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md
    inputs.lanzaboote.nixosModules.lanzaboote
    ./secret.nix
  ];

  boot.lanzaboote.pkiBundle = "/etc/secureboot";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" "repl-flake" ];
  nixpkgs.config.allowUnfree = true;

  boot.kernelModules = [
    "nft_tproxy"
    "nft_socket"
  ];

  # Use nftables backend
  networking.nftables.enable = true;
  networking.firewall.enable = true;
  networking.networkmanager.firewallBackend = "nftables";

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

  # Secrets
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/secrets.yaml;

  i18n.defaultLocale = mkDefault "en_US.UTF-8";

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # This option is not compactiable with flakes
  # system.copySystemConfiguration = true;
}
