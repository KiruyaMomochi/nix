{
  lib,
  fetchurl,
  buildLinux,
  src,
  ...
}@args:

let
  # Patch order follows upstream's kernel/patches/series.
  series = lib.filter (l: l != "" && !lib.hasPrefix "#" l) (
    lib.splitString "\n" (builtins.readFile "${src}/kernel/patches/series")
  );
in
buildLinux (
  builtins.removeAttrs args [ "src" ]
  // {
    version = "7.3.0";
    modDirVersion = "7.3.0";

    src = fetchurl {
      url = "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz";
      sha256 = "0ls902gz6h1ydcnwx2zzdcglg52f14hmaxk2ncg341hfy4j3qdl7";
    };

    kernelPatches = map (name: {
      inherit name;
      patch = "${src}/kernel/patches/${name}";
    }) series;

    # From upstream kernel/config/kernel-local.
    structuredExtraConfig = with lib.kernel; {
      SM_VIDEOCC_8550 = module;
      HID_ASUS_EC = module;
      VIDEO_HM1092 = module;
      # EC driver (fan control); only binds when the experimental DT node is present.
      EC_QCOM_HAMOA = module;
    };

    ignoreConfigErrors = true;
  }
  // (args.argsOverride or { })
)
