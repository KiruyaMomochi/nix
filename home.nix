{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "kyaru";
  home.homeDirectory = "/home/kyaru";

  nixpkgs.config = import ./nixpkgs-config.nix;
  xdg.configFile."nixpkgs/config.nix".source = ./nixpkgs-config.nix;
  nix.package = pkgs.nix;

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    bat
    gh
    glab

    p7zip
    fd # find
    procs # ps
    sd # sed
    bottom # top
    delta # diff
    ripgrep # grep
    erdtree # tree and du
    choose # cut and sometimes awk

    file
    unzip
    ldns

    nil
    nixpkgs-fmt
    nixpkgs-review

    dconf # fix dconf error

    (typst.overrideAttrs (final: previous: {
      src = pkgs.fetchFromGitHub {
        owner = "typst";
        repo = "typst";
        rev = "e70ec5f3c06312b7ff2388630e05e3c2d745896f";
        hash = "sha256-LHS3OUs6za5SOaUvGUcsv2viNX2qPOKcU3QdwzVheYE=";
      };

      TYPST_VERSION = "7sdream-add-font-patch";
    }))
  ];

  home.sessionVariables = {
    EDITOR = "${pkgs.helix}/bin/hx";
  };

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
    lfs.enable = true;
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
    enable = false;
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

  # ls
  programs.exa = {
    enable = true;
    enableAliases = true;
  };

  # top
  programs.htop.enable = true;
  programs.bottom = {
    enable = true;
  };

  # editor
  programs.helix =
    {
      enable = true;
      languages = [
        {
          name = "nix";
          formatter = { command = "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt"; };
        }
      ];
    };

  # tmux
  programs.zellij.enable = true;


  xdg.dataFile."fcitx5/rime/default.custom.yaml".source = (pkgs.formats.yaml { }).generate "default.custom.yaml" {
    patch = {
      schema_list = [
        {
          "schema" = "double_pinyin_flypy";
        }
      ];
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.11";
}
