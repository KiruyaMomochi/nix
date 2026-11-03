{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.kyaru.hyprland;
  inherit (lib) types mkOption mkEnableOption mkIf;
  link = config.lib.file.mkOutOfStoreSymlink;
in
{
  options.programs.kyaru.hyprland = {
    enable = mkEnableOption "Kiruya's Hyprland setup (needs kyaru.desktop.hyprland on the system)";

    repo = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/Projects/nix";
      description = ''
        Checkout of this repo on the machine. hyprland.lua is linked from
        here instead of the store, so edits apply on `hyprctl reload`
        without a switch.
      '';
    };

    scale = mkOption {
      type = types.either types.float (types.enum [ "auto" ]);
      default = "auto";
      example = 1.25;
    };

    softwareCursor = mkOption {
      type = types.bool;
      default = false;
      description = "Draw the cursor in software (msm on X1E shows no hardware cursor).";
    };
  };

  config = mkIf cfg.enable {
    xdg.configFile."hypr/hyprland.lua".source =
      link "${cfg.repo}/homeModules/hyprland/hyprland.lua";
    xdg.configFile."hypr/host.lua".text = ''
      return {
          scale = ${if cfg.scale == "auto" then ''"auto"'' else toString cfg.scale},
          software_cursor = ${lib.boolToString cfg.softwareCursor},
      }
    '';

    home.packages = with pkgs; [ ghostty ];

    # combi = apps + run: text that matches no app runs as a command,
    # so `zen-twilight -P` + Enter just works (Ctrl+Enter forces it).
    programs.rofi = {
      enable = true;
      font = "Sarasa UI SC 12";
      terminal = "ghostty";
      extraConfig = {
        modi = "combi,drun,run";
        combi-modes = "drun,run";
        combi-hide-mode-prefix = true;
        show-icons = true;
        drun-display-format = "{name}";
      };
      theme = ./rofi.rasi;
    };

    # Bind the hypr* user services to the uwsm Hyprland session only.
    # The default graphical-session.target is also up under Plasma.
    wayland.systemd.target = "wayland-session@hyprland.desktop.target";

    services.hyprpolkitagent.enable = true;
    services.swayosd.enable = true;
    services.hyprsunset = {
      enable = true;
      settings.profile = [
        { time = "7:00"; identity = true; }
        { time = "19:00"; temperature = 4000; }
      ];
    };
  };
}
