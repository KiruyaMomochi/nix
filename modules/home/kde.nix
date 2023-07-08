{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    ark
    kcolorchooser
    krita
    kate
    qalculate-qt # latte-dock
    krdc
    libsForQt5.dolphin
    konsole
  ];


  xdg.dataFile."konsole/Breeze.colorscheme" = {
    source =
      let
        concatString = pkgs.lib.concatStringsSep "\n";
        sections = [
          "Background"
          "BackgroundFaint"
          "BackgroundIntense"
          "Foreground"
          "ForegroundFaint"
          "ForegroundIntense"
        ];
        appendRandom = {
          RandomHueRange = 360;
          RandomSaturationRange = 100;
          # RandomLightnessRange = 10;
        };
        general =
          {
            Blur = true;
            ColorRandomization = true;
            Opacity = 0.83;
            Description = "Breeze Randomized";
            FillStyle = "Title";
          };
        breeze = pkgs.runCommand "my-derivation" { } ''
            install -Dm644 "${pkgs.konsole}/share/konsole/Breeze.colorscheme" $out

            # Remove all keys of appendRandom
            ${concatString (
              pkgs.lib.mapAttrsToList (k: v: "sed -i '/${k}=/d' $out") appendRandom
            )}

            # For each section append the new key
            for section in ${pkgs.lib.concatStringsSep " " sections}; do
              ${concatString (
                pkgs.lib.mapAttrsToList (k: v: "sed -i '/\\['$section'\\]/a ${k}=${toString v}' $out") appendRandom
              )}
            done          

            # Remove the full [General] section
            sed -i '/\[General\]/,/\[/d' $out
            # Append the new [General] section
            echo "[General]" >> $out
            ${concatString (
              pkgs.lib.mapAttrsToList (k: v: "echo '${k}=${toString v}' >> $out") general
            )}
        '';
      in
        breeze.out;
  };

}
