{ fetchFromGitHub
, chromium
, lib
, stdenv
, pkgsBuildHost
, python
, openssl
}:
let
  version = "116.0.5845.92-2";
  naiveSrc = fetchFromGitHub {
    repo = "naiveproxy";
    owner = "klzgrad";
    rev = "v${version}";
    sha256 = "sha256-9WcggjS07svbp+EB3WsbX6zLSHO+9hzWje2sdXXfpYs=";
  };

  # Copied from chromium.nix
  libExecPath = "$out/libexec/${self.packageName}";
  # https://source.chromium.org/chromium/chromium/src/+/master:build/linux/unbundle/replace_gn_files.py
  gnSystemLibraries = [
    # TODO:
    # "ffmpeg"
    # "snappy"
    "flac"
    "libjpeg"
    "libpng"
    "libwebp"
    "libxslt"
    # "opus"
  ];
  chromiumRosettaStone = {
    cpu = platform:
      let name = platform.parsed.cpu.name;
      in (
        {
          "x86_64" = "x64";
          "i686" = "x86";
          "arm" = "arm";
          "aarch64" = "arm64";
        }.${platform.parsed.cpu.name}
          or (throw "no chromium Rosetta Stone entry for cpu: ${name}")
      );
    os = platform:
      if platform.isLinux
      then "linux"
      else throw "no chromium Rosetta Stone entry for os: ${platform.config}";
  };
  postPatch = ''
    # Disable build flags that require LLVM 15:
    substituteInPlace build/config/compiler/BUILD.gn \
      --replace '"-Xclang",' ""
    #   --replace '"-no-opaque-pointers",' ""

    # remove unused third-party
    for lib in ${toString gnSystemLibraries}; do
      if [ -d "third_party/$lib" ]; then
        find "third_party/$lib" -type f \
          \! -path "third_party/$lib/chromium/*" \
          \! -path "third_party/$lib/google/*" \
          \! -path "third_party/harfbuzz-ng/utils/hb_scoped.h" \
          \! -regex '.*\.\(gn\|gni\|isolate\)' \
          -delete
      fi
    done

    # Required for patchShebangs (unsupported interpreter directive, basename: invalid option -- '*', etc.):
    if [ -e third_party/harfbuzz-ng/src/src/update-unicode-tables.make ]; then
      substituteInPlace third_party/harfbuzz-ng/src/src/update-unicode-tables.make \
        --replace "/usr/bin/env -S make -f" "/usr/bin/make -f"
    fi

    patchShebangs .
    # Link to our own Node.js (required during the build):
    mkdir -p third_party/node/linux/node-linux-x64/bin
    ln -s "${pkgsBuildHost.nodejs}/bin/node" third_party/node/linux/node-linux-x64/bin/node

  '' + lib.optionalString (stdenv.hostPlatform == stdenv.buildPlatform && stdenv.hostPlatform.isAarch64) ''
    substituteInPlace build/toolchain/linux/BUILD.gn \
      --replace 'toolprefix = "aarch64-linux-gnu-"' 'toolprefix = ""'
  '';

  # Patch gn flags in common.nix
  filterGnFlags = flags_str: filter:
    let
      splitted = lib.strings.splitString " " flags_str;
      toPair = str:
        let
          splitted = lib.strings.splitString "=" str;
          key = builtins.elemAt splitted 0;
          value = lib.lists.concatStrings (lib.lists.drop 1 splitted);
        in
        lib.attrsets.nameValuePair key value;
      toKey = str: (toPair str).name;
      filtered = builtins.filter (p: filter (toKey p)) splitted;
    in
    lib.concatStringsSep " " filtered;

  skipGnFlags = [
    "blink_symbol_level"
    "disable_fieldtrial_testing_config"
    "enable_hangout_services_extension"
    "enable_nacl"
    "enable_widevine"
    "ffmpeg_branding"
    "google_api_key"
    "link_pulseaudio"
    "rtc_use_pipewire"
    "use_cups"
    "use_pulseaudio"
    "use_qt"
    "use_system_libffi"
    "v8_snapshot_toolchain"
  ];
  patchedGnFlags = filterGnFlags self.gnFlags (k: ! (builtins.elem k skipGnFlags));

  self = chromium.mkDerivation
    # rec for buildTargets
    (base: rec {
      inherit version;
      name = "naïveproxy";
      packageName = "naiveproxy";
      buildTargets = [ "naive" ];
      src = naiveSrc + "/src";

      gnFlags = {
        fatal_linker_warnings = false;

        enable_base_tracing = false;
        use_udev = false;
        use_aura = false;
        use_ozone = false;
        use_gio = false;
        use_gtk = false;
        use_platform_icu_alternatives = true;
        use_glib = false;

        disable_file_support = true;
        enable_websockets = false;
        use_kerberos = false;
        enable_mdns = false;
        enable_reporting = false;
        include_transport_security_state_preload_list = false;
        use_nss_certs = false;
      };

      depsBuildBuild = lib.lists.take 4 base.depsBuildBuild;
      buildInputs = [ ];

      # From common.nix of nixpkgs
      patches = (lib.lists.take 2 base.patches) ++ (lib.lists.drop 4 base.patches);
      inherit postPatch;

      buildPhase =
        let
          buildCommand = target: ''
            TERM=dumb ninja -C "${self.buildPath}" -j$NIX_BUILD_CORES "${target}"
          '';
          targets = buildTargets;
          commands = map buildCommand targets;
        in
        ''
          runHook preBuild
          ${lib.concatStringsSep "\n" commands}
          runHook postBuild
        '';

      # patches = lib.lists.drop 4 base.patches;
      configurePhase = ''
        runHook preConfigure

        # This is to ensure expansion of $out.
        libExecPath="${libExecPath}"

        ${self.passthru.chromiumDeps.gn}/bin/gn gen --args=${lib.escapeShellArg patchedGnFlags} out/Release | tee gn-gen-outputs.txt

        # Fail if `gn gen` contains a WARNING.
        grep -o WARNING gn-gen-outputs.txt && echo "Found gn WARNING, exiting nix build" && exit 1

        runHook postConfigure
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/bin"
        install -Dm755 "out/Release/naive" "$out/bin/naiveproxy"
        install -Dm644 "config.json" "$out/share/naiveproxy/config.json"
        install -Dm644 "${naiveSrc}/USAGE.txt" "$out/share/doc/naiveproxy/USAGE.txt"
        install -Dm644 "${naiveSrc}/LICENSE" "$out/share/licenses/naiveproxy/LICENSE"

        runHook postInstall
      '';

      postFixup = null;
      nativeCheckInputs = [ python openssl ];
      checkPhase = ''
        target_cpu="${chromiumRosettaStone.cpu stdenv.hostPlatform}"
        python3 "${naiveSrc}/tests/basic.py" --naive="$naive" --target_cpu="$target_cpu" --server_protocol=https
        python3 "${naiveSrc}/tests/basic.py" --naive="$naive" --target_cpu="$target_cpu" --server_protocol=http
      '';
    });
in
self
