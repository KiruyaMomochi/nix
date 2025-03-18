{ fetchFromGitHub
  # This is in https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/browsers/chromium/default.nix
, chromium
, lib
, stdenv
, pkgsBuildHost
, python
, openssl
, libpng
, python3
}:
let
  version = "134.0.6998.39-1";
  hash = "sha256-SW6VJN61rm0jZDlrI13uNSoQC6LPhUZVnVJg98/P754=";
  naiveSrc = fetchFromGitHub {
    repo = "naiveproxy";
    owner = "klzgrad";
    rev = "v${version}";
    sha256 = "sha256-1jjpqrWaenNDmSQ+QxbpUACD3ROEjaD5nj1HykeVYuA=";
  };

  packageName = self.packageName;

  # Make chromium library functions use the correct version
  # chroimum.mkDerivation (default.nix) -> callPackage common.nix
  mkChromiumDerivation = (chromium.override (previous: {
    upstream-info = chromium.upstream-info // {
      inherit version;
      DEPS = builtins.removeAttrs chromium.upstream-info.DEPS [ "src" ];
    };
    # newScope = chromium: packagePath: overrideArgs: ((previous.newScope chromium) packagePath overrideArgs);
  })).mkDerivation.override (previous: {
    stdenv = previous.stdenv // {
      mkDerivation = args: previous.stdenv.mkDerivation (args // {
        gn = "${previous.gnChromium}/bin/gn";
      });
    };
  });

  # Copied from https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/browsers/chromium/common.nix

  # actually, we don't use any of these libraries
  gnSystemLibraries = [ ];
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
    # Skipping isElectron patches from commit 8dd2f1a: fetch src from git instead of using release tarball
  '' + ''
    # Workaround/fix for https://bugs.chromium.org/p/chromium/issues/detail?id=1313361:
    substituteInPlace BUILD.gn \
      --replace '"//infra/orchestrator:orchestrator_all",' ""
    # Disable build flags that require LLVM 15:
    substituteInPlace build/config/compiler/BUILD.gn \
      --replace '"-Xclang",' "" \
      --replace '"-no-opaque-pointers",' ""
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

    # skip setuid_sandbox_host patch
    # skip audio_sandbox_hook_linux patch
  '' + ''
    # chrome_paths does not exist

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
    "use_qt5"
    "use_qt6"
    "use_system_libffi"
    "v8_snapshot_toolchain"

    # Rust toolchain is enabled since https://github.com/NixOS/nixpkgs/commit/1724fc3271f3447b8c741216af9b8c66151032a8
    # But because it's not required by naiveproxy, and naive has removed related source files, while keeping build gn files, the build will fail.
    # We just drop rust support here.
    "rust_sysroot_absolute"
    "enable_rust"
  ];
  patchedGnFlags = filterGnFlags self.gnFlags (k: ! (builtins.elem k skipGnFlags));

  # mkChromiumDerivation Modified at the beginning of this file.
  # The original function is defined in https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/browsers/chromium/default.nix
  self = mkChromiumDerivation
    # rec for buildTargets
    # `buildFun base` is extraAttrs in common.nix
    (base: rec {
      inherit version;
      pname = "naiveproxy";
      packageName = "naiveproxy";
      buildTargets = [ "naive" ];
      src = naiveSrc + "/src";

      # https://github.com/klzgrad/naiveproxy/blob/master/src/build.sh#L46
      gnFlags = {
        fatal_linker_warnings = false;

        is_cronet_build = true;
        # # LLVM 12: unsupported instrumentation profile format version
        # chrome_pgo_phase = 2;
        # # https://github.com/NixOS/nixpkgs/pull/101786
        # pgo_data_path =
        #   builtins.toString (builtins.fetchurl {
        #     # https://github.com/chromium/chromium/blob/130.0.6723.40/chrome/build/linux.pgo.txt
        #     url = "https://commondatastorage.googleapis.com/chromium-optimization-profiles/pgo_profiles/chrome-linux-6723-1728387217-9f5646f93bc4ba3a2a9310010e81c26b70db13b1-f044eaa32696eb5c9c4d3ffede525cf50c8cc3e9.profdata";
        #     sha256 = "sha256:1libr521l97y6z22dmsxzwg68i6kmmhsha7a176fsq6xbwi40whm";
        #   });

        enable_base_tracing = false;
        use_udev = false;
        use_aura = false;
        use_ozone = false;
        use_gio = false;
        use_gtk = false;
        use_platform_icu_alternatives = true;
        use_glib = false;

        disable_file_support = true;
        disable_zstd_filter = false;
        enable_websockets = false;
        use_kerberos = false;
        enable_mdns = false;
        enable_reporting = false;
        include_transport_security_state_preload_list = false;
        enable_device_bound_sessions = false;
        enable_bracketed_proxy_uris = true;

        use_nss_certs = false;
      } // (lib.optionalAttrs stdenv.hostPlatform.isx86 {
        # https://github.com/klzgrad/naiveproxy/commit/f5034cd7da67f063724dc27fdf0a42384db84379
        use_cfi_icall = false;
      });

      depsBuildBuild = lib.lists.remove libpng (base.depsBuildBuild or [ ]);
      buildInputs = [ openssl ];

      ignoredPatches = [
        "widevine-disable-auto-download-allow-bundle.patch"
        "angle-wayland-include-protocol.patch"
        "chromium-initial-prefs.patch"
        # qr code generator
        "https://github.com/chromium/chromium/commit/bcf739b95713071687ff25010683248de0092f6a.patch"
        # webui_name_variants
        "https://github.com/chromium/chromium/commit/2c101186b60ed50f2ba4feaa2e963bd841bcca47.patch"
        "https://github.com/chromium/chromium/commit/f2b43c18b8ecfc3ddc49c42c062d796c8b563984.patch"
        "https://github.com/chromium/chromium/commit/4ca70656fde83d2db6ed5a8ac9ec9e7443846924.patch"
        "https://github.com/chromium/chromium/commit/50d63ffee3f7f1b1b9303363742ad8ebbfec31fa.patch"
        # rust std::hardware_destructive_interference_size
        "https://github.com/chromium/chromium/commit/fc838e8cc887adbe95110045d146b9d5885bf2a9.patch"
      ];
      # From common.nix of nixpkgs
      patches =
        let
          basePatches = builtins.filter
            (p:
              if builtins.typeOf p == "path" && (builtins.elem (builtins.baseNameOf p) ignoredPatches) then false
              else if builtins.typeOf p == "set" && p ? url && (builtins.elem p.url ignoredPatches) then false
              else true
            )
            base.patches;
        in
        basePatches;

      inherit postPatch;


      # Upstream is using Google's src, so we remove it and use our own.
      postUnpack = ''
        cp -r $src/. src
        chmod u+w -R src
      '';

      # Ignore nodejs
      npmRoot = null;
      npmDeps = null;
      preConfigure = null;
      nativeBuildInputs = lib.lists.reverseList (lib.lists.drop 2 (lib.lists.reverseList base.nativeBuildInputs));

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
        ${python3.pythonOnBuildForHost}/bin/python3 build/linux/unbundle/replace_gn_files.py --system-libraries ${toString gnSystemLibraries}
        $gn gen --args=${lib.escapeShellArg patchedGnFlags} out/Release | tee gn-gen-outputs.txt

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
        mainProgram = "naive";
      };
    });
in
self
