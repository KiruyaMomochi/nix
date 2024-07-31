{ inputs, config, pkgs, lib, ... }:

{
  imports = [
    {
      nixpkgs.overlays = [
        inputs.self.overlay
      ];
    }
  ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "kyaru";
  home.homeDirectory = "/home/${config.home.username}";

  nixpkgs.config = lib.mkDefault (import ./nixpkgs-config.nix);
  xdg.configFile."nixpkgs/config.nix".source = lib.mkDefault ./nixpkgs-config.nix;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };
  nix.package = pkgs.nixVersions.latest;


  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # utils
    bat # cat
    fd # find
    procs # ps
    sd # sed
    btop # htop
    delta # diff
    ripgrep # grep
    erdtree # tree and du
    choose # cut and sometimes awk
    comma # quickly run command
    lurk # strace
    aria
    lnav
    pciutils # lspci

    # common commands
    file
    unzip
    ldns
    tldr
    p7zip
    jq
    yq

    # nix related
    nil
    nixpkgs-fmt
    nixpkgs-review
    cachix
    nix-output-monitor
    expect

    # for developing
    gh
    glab
    gitui
    shellcheck
    shfmt

    # others
    dconf # fix dconf error
    typst
    # typst-lsp # not working
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
    plugins = [ ];
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
    enable = lib.mkDefault false;
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
      # https://github.com/nix-community/home-manager/pull/4749
      version = "1";
    };
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };

  # ls
  programs.eza = {
    enable = true;
  };

  # top
  programs.htop.enable = true;

  # editor
  programs.helix =
    {
      enable = true;
      settings = {
        editor.soft-wrap.enable = true;
      };
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

  services.vscode-server.enable = true;

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
  home.stateVersion = "24.05";
}
