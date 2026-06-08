{
  lib,
  chromium,
  fetchFromGitHub,
}:

let
  naiveproxy-src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "naiveproxy";
    # From https://github.com/SagerNet/cronet-go
    rev = "2be061b6c2e9b316f75ec1e329e345406cd4c62d";
    hash = "sha256-eK3t8YmXnmPptQMSuKTne+Ro+G+u5BWXHrX/Nh4VYvo=";
  };
in

# Use mkChromiumDerivation to get the environment and source for free
chromium.mkDerivation (base: rec {
  name = "libcronet-naive";
  packageName = "libcronet";

  # Canonical target
  buildTargets = [ "components/cronet:cronet" ];

  # "SageNet Style" GN flags (Copied from cronet-go/cmd/build-naive/cmd_build.go)
  gnFlags = {
    # Common flags
    is_official_build = true;
    is_debug = false;
    is_clang = true;
    use_clang_modules = false;
    use_thin_lto = false;
    fatal_linker_warnings = false;
    treat_warnings_as_errors = false;
    is_cronet_build = true;
    use_udev = false;
    use_aura = false;
    use_ozone = false;
    use_gio = false;
    use_glib = false;
    use_kerberos = false;
    disable_zstd_filter = false;
    enable_reporting = false;
    enable_bracketed_proxy_uris = true;
    enable_quic_proxy_support = true;
    use_nss_certs = false;
    enable_backup_ref_ptr_support = false;
    enable_dangling_raw_ptr_checks = false;
    exclude_unwind_tables = true;
    enable_resource_allowlist_generation = false;
    symbol_level = 0;
    enable_dsyms = false;
    optimize_for_size = true;

    # CFI Config (Must match use_thin_lto=false)
    use_cfi_icall = false;
    is_cfi = false;

    target_os = "linux";
    target_cpu = "x64";

    # We disable sysroot because we are in Nix environment
    use_sysroot = false;

    # Note: We do NOT set use_platform_icu_alternatives (Let it default)
  };

  # Overlay NaiveProxy source BEFORE patches are applied.
  # The chromium base provides LLVM compatibility patches (e.g. chromium-147-llvm-22.patch,
  # chromium-148-revert-build-Add--fsanitizer=return-config.patch) that fix
  # `unknown argument: -fno-lifetime-dse`, `-fsanitize-ignore-for-ubsan-feature=*` errors
  # against LLVM 21. If we overlay naive's src *after* patches, those fixes get reverted
  # and the build breaks on those unknown clang flags. Apply via prePatch so the chromium
  # patches land on naive's tree.
  prePatch = ''
    echo "Overlaying NaiveProxy source..."
    cp -rf ${naiveproxy-src}/src/* .
    if [ -f "${naiveproxy-src}/src/.gn" ]; then
      cp -f "${naiveproxy-src}/src/.gn" .
    fi
    # fetchFromGitHub stores files read-only; chromium's postPatch (and our own)
    # needs to overwrite them. Restore write permission on the overlay.
    chmod -R u+w .
    echo "Overlay complete."
  '';

  # Drop chromium-147-llvm-22.patch because naive's build/config/compiler/BUILD.gn
  # carries an extra `&& !is_apple` clause around the `-fno-lifetime-dse` block,
  # so the hunk context doesn't match. We strip the flag ourselves in postPatch instead.
  patches = lib.filter (
    p: !(lib.hasSuffix "llvm-22.patch" (p.name or (toString p)))
  ) base.patches;

  # Inherit chromium's enormous postPatch (LASTCHANGE, sandbox paths, system-libs filtering,
  # node/java symlinks, gperf shim, etc.) and tack on naive-specific tweaks:
  #   * Drop the `cflags += [ "-fno-lifetime-dse" ]` line (replaces chromium-147-llvm-22.patch).
  postPatch = (base.postPatch or "") + ''
    echo "Stripping -fno-lifetime-dse for LLVM 21 compatibility (naive-adapted)..."
    substituteInPlace build/config/compiler/BUILD.gn \
      --replace-warn 'cflags += [ "-fno-lifetime-dse" ]' '# -fno-lifetime-dse stripped for LLVM 21'
  '';

  # Configure Phase: Just run GN.
  configurePhase = ''
    runHook preConfigure

    # Run the replacement script for system libs
    # Do we need this if use_sysroot=false?
    # Yes, if we use system libs. But we disabled glib/nss.
    # Maybe we don't need this?
    # Let's run it anyway to avoid include errors if defaults pick system libs.
    # python3 build/linux/unbundle/replace_gn_files.py --system-libraries flac libjpeg libpng libxml libxslt

    echo "Running gn gen..."
    # naive ships a chromium *subset* — many BUILD.gn declarations (perfetto
    # unittests, base/test:test_support, etc.) survive but their implementation
    # files were stripped, so `gn gen` from the default root fails with
    # "Unresolved dependencies." We work around this with two flags:
    #
    #   --root-target=//components/cronet
    #     Override the initial BUILD.gn loaded for graph population, skipping
    #     the //BUILD.gn `gn_all` group which references things like
    #     `optimize_gn_gen` that pull in chromium-only targets.
    #     (See `gn help --root-target`.)
    #
    #   --root-pattern='//components/cronet:*'
    #     Even with a custom root, GN by default loads every reachable BUILD.gn;
    #     this pattern caps the default-toolchain target set to cronet and its
    #     transitive deps only. `:*` matches targets *in* that file (incl. the
    #     `shared_library("cronet")` we want); `/*` only matches subdirs.
    #     (See `gn help --root-pattern` and `gn help label_pattern`.)
    gn gen --args="$gnFlags" \
      --root-target=//components/cronet \
      --root-pattern='//components/cronet:*' \
      out/Release

    runHook postConfigure
  '';

  # Install Phase
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/include

    echo "Installing libcronet.so..."
    SO_FILE=$(find out/Release -name "libcronet.so" -o -name "libcronet.*.so" | head -n 1)

    if [ -n "$SO_FILE" ]; then
      echo "Found library at: $SO_FILE"
      cp "$SO_FILE" $out/lib/
      if [[ "$(basename "$SO_FILE")" != "libcronet.so" ]]; then
        ln -s "$(basename "$SO_FILE")" $out/lib/libcronet.so
      fi
      
      # Check for icudtl.dat
      if [ -f "out/Release/icudtl.dat" ]; then
         echo "Installing icudtl.dat..."
         cp "out/Release/icudtl.dat" $out/lib/
      else
         echo "Warning: icudtl.dat not found! (Checking if build works)"
      fi
    else
      echo "Error: libcronet.so not found!"
      exit 1
    fi

    echo "Installing headers..."
    if [ -d "components/cronet/native/include" ]; then
      find components/cronet/native/include -name "*.h" -exec cp {} $out/include/ \;
    fi
    if [ -d "components/cronet/native/generated" ]; then
      find components/cronet/native/generated -name "*.h" -exec cp {} $out/include/ \;
    fi
    if [ -d "components/grpc_support/include" ]; then
      find components/grpc_support/include -name "*.h" -exec cp {} $out/include/ \;
    fi
      
    runHook postInstall
  '';

  postFixup = "";

  meta = with lib; {
    description = "Libcronet built from Hybrid Source (SageNet Config)";
    platforms = platforms.linux;
  };
})
