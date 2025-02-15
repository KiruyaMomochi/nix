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
  home.packages = (with pkgs; [
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
  ]) ++ (with pkgs.nushellPlugins; [
    polars
    formats
    gstat
    query
  ]);

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
      setw -g mode-keys vi
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
    lfs = {
      enable = true;
      skipSmudge = true;
    };
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
    enableNushellIntegration = false;
  };

  # top
  programs.htop.enable = true;

  # shell completion
  programs.carapace = {
    enable = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = true;
  };
  xdg.configFile."carapace/bridges.yaml".source =
    (pkgs.formats.yaml { }).generate "bridges.yaml" {
      nix = "fish";
      ssh = "fish";
      scp = "fish";
      rsync = "fish";
    };

  programs.nushell = {
    enable = true;
    # # https://github.com/nushell/nushell/blob/main/crates/nu-utils/src/default_files/default_config.nu
    configFile.source = ./homeModules/nushell/config.nu;
    # # https://github.com/nushell/nushell/blob/main/crates/nu-utils/src/default_files/default_env.nu
    envFile.source = ./homeModules/nushell/env.nu;
    environmentVariables = {
      CARAPACE_BRIDGES = (lib.strings.concatStringsSep "," [ "fish" "bash" "inshellisense" ]);
      CARAPACE_EXCLUDES = (lib.strings.concatStringsSep "," [
        "nix" # just use the one from fish/bash
        "scp"
        "rsync" # fish implementation is much better
      ]);
    };
    extraConfig = lib.strings.concatStringsSep "\n" [
      ''
        $env.config.hooks.command_not_found = { |cmd_name|
          try {
            let commands = (^"${config.programs.nix-index.package}/bin/nix-locate" --type x --type s --top-level --whole-name --at-root $"/bin/($cmd_name)" | lines | split column --collapse-empty " " name size type path)
            if ($commands | is-empty) {
              return null
            }
            let $pkgs = ($commands | get name | str join " ")
            return (
              $"(ansi $env.config.color_config.shape_external)($cmd_name)(ansi reset) " +
              $"may be found in the following packages:\n($pkgs)"
            )
          }
        }

        hide-env TRANSIENT_PROMPT_COMMAND_RIGHT
      ''
    ];
  };

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
        {
          name = "sshclientconfig";
          file-types = [
            { glob = ".ssh/config"; }
            { glob = ".ssh/config.d/*"; }
            { glob = "/etc/ssh/ssh_config"; }
            { glob = "/etc/ssh/ssh_config.d/*"; }
          ];
        }
      ];
    };

  programs.starship = {
    enable = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    enableTransience = true;
    settings = builtins.fromTOML (builtins.readFile ./homeModules/starship/config.toml);
  };
  programs.kyaru.starship.presets = [ "nerd-font-symbols" ];
  # https://starship.rs/guide/#%F0%9F%9A%80-installation
  xdg.dataFile."nushell/vendor/autoload/starship.nu".source = pkgs.runCommand "starship.nu" {} ''
    ${config.programs.starship.package}/bin/starship init nu > $out
    echo '$env.PROMPT_INDICATOR = "> "' >> $out
    echo '$env.TRANSIENT_PROMPT_COMMAND = ""' >> $out
  '';

  # tmux
  programs.zellij = {
    enable = true;
    settings = {
      default_shell = "${pkgs.nushell}/bin/nu";
    };
  };

  programs.nix-index-database.comma.enable = true;
  programs.nix-index.enable = true;

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

  # User directories
  # https://wiki.archlinux.org/title/XDG_user_directories
  # xdg.userDirs.enable = true;
  xdg.userDirs.createDirectories = true;

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
  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;
}
