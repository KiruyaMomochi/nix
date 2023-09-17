{ inputs, config, pkgs, ... }:

{
  imports = [
    {
      nixpkgs.overlays = [ inputs.self.overlay ];
    }
    inputs.vscode-server.nixosModules.home
    inputs.self.homeModules.all
  ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "kyaru";
  home.homeDirectory = "/home/${config.home.username}";

  programs.kyaru = {
    desktop.enable = true;
    kde.enable = true;
  };
  services.onedrive-rclone.enable = true;

  nixpkgs.config = import ./nixpkgs-config.nix;
  xdg.configFile."nixpkgs/config.nix".source = ./nixpkgs-config.nix;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" "repl-flake" ];
    extra-trusted-public-keys = [ "usc1-nix-cache-1:0eeX8bNNyT/i++0MP6ZA6VeuXmsm0tw5Lkb4R4x5Fkg=" ];
  };
  nix.package = pkgs.nix;

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # utils
    bat # cat
    fd # find
    procs # ps
    sd # sed
    bottom # top
    btop # htop
    delta # diff
    ripgrep # grep
    erdtree # tree and du
    choose # cut and sometimes awk
    comma # quickly run command

    # common commands
    file
    unzip
    ldns
    tldr
    p7zip
    gh
    glab
    gitui

    # nix related
    nil
    nixpkgs-fmt
    nixpkgs-review
    cachix
    nix-output-monitor
    expect

    # others
    dconf # fix dconf error
    typst
    typst-lsp
    rclone

    awscli2
  ];

  home.sessionVariables = {
    EDITOR = "${pkgs.helix}/bin/hx";
  };

  home.shellAliases = {
    "ip" = "ip -c";
    "cp" = "cp -v";
  };

  programs.fish = {
    enable = true;
    plugins = [
      rec {
        name = "puffer-fish";
        src = pkgs.fetchFromGitHub {
          owner = "nickeb96";
          repo = name;
          rev = "5d3cb25e0d63356c3342fb3101810799bb651b64";
          sha256 = "sha256-aPxEHSXfiJJXosIm7b3Pd+yFnyz43W3GXyUB5BFAF54=";
        };
      }
      # rec {
      #   name = "tide";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "IlanCosman";
      #     repo = name;
      #     rev = "6a9d3e2749f0cc109604167ec9497ccda5c62d98";
      #     sha256 = "sha256-8zPAqlM7f7dISsCsl6zdArufQ4VhCMSQccUslTpK9bM=";
      #   };
      # }
    ];
  };

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
    includes = [
      {
        path = "config.extra";
      }
    ];

    delta.enable = true;
    lfs.enable = true;
    extraConfig = {
      init.defaultBranch = "main";
    };
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
    gitCredentialHelper.enable = true;
    settings = {
      prompt = true;
      editor = config.home.sessionVariables.EDITOR;
    };
  };

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  # ls
  programs.eza = {
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
      languages.language = [
        {
          name = "nix";
          formatter = { command = "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt"; };
        }
      ];
    };

  # tmux
  programs.zellij = {
    enable = true;
    settings = {
      default_shell = "${config.programs.fish.package}/bin/fish";
    };
  };

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
