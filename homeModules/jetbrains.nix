{ config, pkgs, jetbrains-pkgs, lib, stdenv, ... }:
let
  cfg = config.programs.kyaru.jetbrains;

  # Copilot
  plugins = jetbrains-pkgs.jetbrains.plugins;
  copilotInfo = rec {
    name = "github-copilot-intellij";
    id = 17718;
    updateId = 268309;
    version = "1.1.38.2229";
    url = "https://plugins.jetbrains.com/files/${toString id}/${toString updateId}/${name}-${version}.zip";
    hash = "sha256-emHd2HLNVgeR9yIGidaE76KWTtvilgT1bieMEn6lDIk=";
    special = true;
  };
  copilot-plugin =
    pkgs.stdenv.mkDerivation (copilotInfo // {
      src = plugins.fetchPluginSrc copilotInfo;
      installPhase = "mkdir $out && cp -r . $out";
      # hash = "";
      inputs = [ pkgs.patchelf pkgs.glibc pkgs.gcc-unwrapped ];
      patchPhase =
        let libPath = lib.makeLibraryPath [ pkgs.glibc pkgs.gcc-unwrapped ]; in
        ''
          agent="copilot-agent/bin/copilot-agent-linux"
          orig_size=$(stat --printf=%s $agent)
          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $agent
          patchelf --set-rpath ${libPath} $agent
          chmod +x $agent
          new_size=$(stat --printf=%s $agent)
          # https://github.com/NixOS/nixpkgs/pull/48193/files#diff-329ce6280c48eac47275b02077a2fc62R25
          ###### zeit-pkg fixing starts here.
          # we're replacing plaintext js code that looks like
          # PAYLOAD_POSITION = '1234                  ' | 0
          # [...]
          # PRELUDE_POSITION = '1234                  ' | 0
          # ^-----20-chars-----^^------22-chars------^
          # ^-- grep points here
          #
          # var_* are as described above
          # shift_by seems to be safe so long as all patchelf adjustments occur 
          # before any locations pointed to by hardcoded offsets
          var_skip=20
          var_select=22
          shift_by=$(expr $new_size - $orig_size)
          function fix_offset {
            # $1 = name of variable to adjust
            location=$(grep -obUam1 "$1" $agent | cut -d: -f1)
            location=$(expr $location + $var_skip)
            value=$(dd if=$agent iflag=count_bytes,skip_bytes skip=$location \
             bs=1 count=$var_select status=none)
            value=$(expr $shift_by + $value)
            echo -n $value | dd of=$agent bs=1 seek=$location conv=notrunc
          }
          fix_offset PAYLOAD_POSITION
          fix_offset PRELUDE_POSITION
        '';
    });
  clion = plugins.addPlugins pkgs.jetbrains.clion [ copilot-plugin ];
in
{
  options.programs.kyaru.jetbrains = {
    enable = lib.mkEnableOption "Kiruya's jetbrains packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      clion
    ];
  };
}
