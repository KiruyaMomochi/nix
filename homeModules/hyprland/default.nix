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

    # adw-gtk3: DMS copies it and patches in its colors (Apply GTK colors); Chrome in GTK mode reads that.
    home.packages = with pkgs; [ hyprshot qtengine adw-gtk3 ];

    # dankcolors is written by DMS on every wallpaper/theme change; it signals ghostty to reload.
    programs.ghostty = {
      enable = true;
      settings = {
        theme = "dankcolors";
        app-notifications = "no-clipboard-copy,no-config-reload";
      };
    };

    # DMS runs custom matugen templates from here alongside its own.
    # Telegram Desktop reloads an imported local theme when the file changes;
    # import it once via Chat settings > ⋮ > Create new theme > Import.
    # Template: github.com/InioX/matugen-themes templates/telegram.tdesktop-theme
    xdg.configFile."matugen/config.toml".text = ''
      [config]

      [templates.telegram]
      input_path = '${./telegram.tdesktop-theme}'
      output_path = '${config.xdg.configHome}/telegram/matugen.tdesktop-theme'

      # Pick "matugen" in btop's options; btop.conf stays btop's own so it can save settings.
      [templates.btop]
      input_path = '${./btop.theme}'
      output_path = '${config.xdg.configHome}/btop/themes/matugen.theme'

      # Linked into /etc/opt/chrome/policies/managed by the NixOS desktop module.
      [templates.chrome]
      input_path = '${pkgs.writeText "chrome-policy.json" ''{ "BrowserThemeColor": "{{colors.primary.default.hex}}" }''}'
      output_path = '${config.xdg.configHome}/dms/chrome-policy.json'
    '';

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

    # XDG_CURRENT_DESKTOP is Hyprland:KDE, so this KDE-only autostart also runs here and
    # reopens whatever was open at the last Plasma logout (Remmina, plasmashell).
    xdg.configFile."autostart/org.kde.plasma-fallback-session-restore.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Plasma Session Restore
      Exec=${pkgs.kdePackages.plasma-workspace}/libexec/plasma-fallback-session-restore
      OnlyShowIn=KDE;
      NotShowIn=Hyprland;
      NoDisplay=true
      X-KDE-StartupNotify=false
    '';
    # Volume/brightness OSD and night light come from DMS now (see programs.dux-shell).
  };
}
