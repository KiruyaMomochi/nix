{ fetchFromGitHub
, chromium
, lib
, stdenv
, pkgsBuildHost
, python
, openssl
, libpng
}:
let
  version = "120.0.6099.43-1";
  naiveSrc = fetchFromGitHub {
    repo = "naiveproxy";
    owner = "klzgrad";
    rev = "v${version}";
    sha256 = "sha256-+t4HRrg8dPqPs4Ay5dTgwVi9y4EIn3KI6otX0WaJUA4=";
  };
  packageName = self.packageName;

  # Copied from https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/browsers/chromium/common.nix

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
  libExecPath = "$out/libexec/${packageName}";
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
      # --replace '"-no-opaque-pointers",' ""

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

    if [[ -e native_client/SConstruct ]]; then
      # Required for patchShebangs (unsupported interpreter directive, basename: invalid option -- '*', etc.):
      substituteInPlace native_client/SConstruct --replace "#! -*- python -*-" ""
    fi
    if [ -e third_party/harfbuzz-ng/src/src/update-unicode-tables.make ]; then
      substituteInPlace third_party/harfbuzz-ng/src/src/update-unicode-tables.make \
        --replace "/usr/bin/env -S make -f" "/usr/bin/make -f"
    fi
    if [ -e third_party/webgpu-cts/src/tools/run_deno ]; then
      chmod -x third_party/webgpu-cts/src/tools/run_deno
    fi
    if [ -e third_party/dawn/third_party/webgpu-cts/tools/run_deno ]; then
      chmod -x third_party/dawn/third_party/webgpu-cts/tools/run_deno
    fi
  '' + ''
    # Add final newlines to scripts that do not end with one.
    # This is a temporary workaround until https://github.com/NixOS/nixpkgs/pull/255463 (or similar) has been merged,
    # as patchShebangs hard-crashes when it encounters files that contain only a shebang and do not end with a final
    # newline.
    find . -type f -perm -0100 -exec sed -i -e '$a\' {} +

    patchShebangs .

    # Link to our own Node.js (required during the build):
    mkdir -p third_party/node/linux/node-linux-x64/bin
    ln -s "${pkgsBuildHost.nodejs}/bin/node" third_party/node/linux/node-linux-x64/bin/node

    # third_party/jdk/current/bin and generate_shim_headers will fail
  '' + lib.optionalString (stdenv.hostPlatform == stdenv.buildPlatform && stdenv.hostPlatform.isAarch64) ''
    substituteInPlace build/toolchain/linux/BUILD.gn \
      --replace 'toolprefix = "aarch64-linux-gnu-"' 'toolprefix = ""'
  '';

  # Patch gn flags in common.nix
  # We first restore the key-value pair,
  # then filter out the flags that does not exist in naiveproxy.
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

  # mkChromiumDerivation defined in https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/browsers/chromium/default.nix
  self = chromium.mkDerivation
    # rec for buildTargets
    # `buildFun base` is extraAttrs in common.nix
    (base: rec {
      inherit version;
      name = "naiveproxy";
      packageName = "naiveproxy";
      buildTargets = [ "naive" ];
      src = naiveSrc + "/src";

      # https://github.com/klzgrad/naiveproxy/blob/master/src/build.sh#L46
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

      depsBuildBuild = lib.lists.remove libpng (base.depsBuildBuild or [ ]);
      buildInputs = [ openssl ];

      ignoredPatches = [
        "widevine-79.patch"
        "angle-wayland-include-protocol.patch"
      ];
      # From common.nix of nixpkgs
      # patches = (lib.lists.take 2 base.patches) ++ (lib.lists.drop 4 base.patches);
      patches = builtins.filter
        (p:
          if builtins.typeOf p == "path" && (builtins.elem (builtins.baseNameOf p) ignoredPatches) then false
          else true
        )
        base.patches;
      inherit postPatch;

      # See common.nix of nixpkgs
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
        install -Dm755 "out/Release/naive" "$out/bin/naive"
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

      meta = with lib; {
        homepage = "https://github.com/klzgrad/naiveproxy";
        description = "naiveproxy";
        platforms = platforms.linux;
      };
    });
in
self
