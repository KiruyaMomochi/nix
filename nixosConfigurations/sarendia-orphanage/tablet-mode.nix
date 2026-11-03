{ pkgs, ... }:
let
  # Flip KWin between tablet and laptop mode. KWin picks up the kwinrc change
  # by itself; plasmashell's OSD says which mode we ended up in.
  toggle = pkgs.writeShellApplication {
    name = "tablet-mode-toggle";
    runtimeInputs = [ pkgs.systemd pkgs.kdePackages.kconfig ];
    text = ''
      current=$(busctl --user get-property org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager tabletMode)
      if [ "$current" = "b true" ]; then
        mode=off icon=input-keyboard text="笔记本模式"
      else
        mode=on icon=input-tablet text="平板模式"
      fi
      kwriteconfig6 --notify --file kwinrc --group Input --key TabletMode "$mode"
      busctl --user call org.kde.plasmashell /org/kde/osdService org.kde.osdService showText ss "$icon" "$text"
    '';
  };

  # The hinge sends nothing to Linux (keyboard, EC, GPIO and lid switch all
  # stay quiet when folded), so a swipe up from the bottom edge stands in for
  # it. The keyboard pops up on its own when a finger touches a text field.
  script = pkgs.runCommand "kwin-script-tablet-mode-swipe" { } ''
    dir=$out/share/kwin/scripts/tablet-mode-swipe
    mkdir -p $dir/contents/code
    cat > $dir/metadata.json <<'EOF'
    {
      "KPlugin": {
        "Id": "tablet-mode-swipe",
        "Name": "Tablet mode swipe",
        "Description": "Swipe up from the bottom edge to toggle tablet mode",
        "Version": "1.0",
        "License": "MIT",
        "EnabledByDefault": true
      },
      "X-Plasma-API": "javascript",
      "X-Plasma-MainScript": "code/main.js",
      "KPackageStructure": "KWin/Script"
    }
    EOF
    cat > $dir/contents/code/main.js <<'EOF'
    registerTouchScreenEdge(KWin.ElectricBottom, function () {
        callDBus("org.freedesktop.systemd1", "/org/freedesktop/systemd1",
                 "org.freedesktop.systemd1.Manager", "StartUnit",
                 "tablet-mode-toggle.service", "replace");
    });
    EOF
  '';
in
{
  environment.systemPackages = [ script ];

  systemd.user.services.tablet-mode-toggle = {
    description = "Toggle KWin tablet mode";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${toggle}/bin/tablet-mode-toggle";
    };
  };
}
