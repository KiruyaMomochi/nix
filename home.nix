{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "kyaru";
  home.homeDirectory = "/home/kyaru";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    bat
    tmux
    helix
    gh
    glab

    htop
    p7zip
    fd # find
    procs # ps
    sd # sed
    bottom # top
    exa # ls
    delta # diff
    ripgrep # grep

    file
    unzip
    ldns

    nil
    nixpkgs-fmt
  ];

  home.sessionVariables = {
    EDITOR = "${pkgs.helix}/bin/hx";
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.11";

  programs.fish.enable = true;

  programs.tmux = {
    enable = true;
    plugins = with pkgs; [
      tmuxPlugins.tmux-thumbs
    ];
    terminal = "tmux-256color";

    extraConfig = ''
      set -g mouse on
    '';
  };

  programs.git = {
    enable = true;
    userName = "百地 希留耶";
    userEmail = "65301509+KiruyaMomochi@users.noreply.github.com";
    signing = {
      key = "0xE3F508DE86FF810F";
      signByDefault = true;
    };
    delta.enable = true;
  };

  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    # defaultCacheTtl = 1800;
    # enableSshSupport = true;
  };

  programs.ssh = {
    enable = true;
    includes = [ "~/.ssh/config.d/*" ];
    matchBlocks = {
      "github.com" = {
        hostname = "ssh.github.com";
        port = 443;
        user = "git";
      };
    };
  };

  programs.gh = {
    enable = true;
    enableGitCredentialHelper = true;
    settings = {
      prompt = true;
      editor = config.home.sessionVariables.EDITOR;
    };
  };

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  programs.exa = {
    enable = true;
    enableAliases = true;
  };

  programs.bottom = {
    enable = true;
  };

  programs.helix.enable = true;

  nix = {
    package = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
