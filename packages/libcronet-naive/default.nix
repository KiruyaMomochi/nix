{ lib
, chromium
, fetchFromGitHub
}:

let
  naiveproxy-src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "naiveproxy";
    rev = "cronet-go";
    hash = "sha256-7VscpFg//oDFDY07oUMDvrOleOXylDMTGvBGH9MlzuI=";
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

  # Overlay NaiveProxy source
  postPatch = (base.postPatch or "") + ''
    echo "Overlaying NaiveProxy source..."
    cp -rf ${naiveproxy-src}/src/* .
    if [ -f "${naiveproxy-src}/src/.gn" ]; then
      cp -f "${naiveproxy-src}/src/.gn" .
    fi
    echo "Overlay complete."
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
    gn gen --args="$gnFlags" out/Release
    
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
      cp -r components/cronet/native/include/* $out/include/
    fi
    if [ -d "components/cronet/native/include" ]; then
      cp -r components/cronet/native/generated/* $out/include/
    fi
    if [ -d "components/grpc_support/include" ]; then
      cp -r components/grpc_support/include/* $out/include/
    fi
      
    runHook postInstall
  '';

  postFixup = "";

  meta = with lib; {
    description = "Libcronet built from Hybrid Source (SageNet Config)";
    platforms = platforms.linux;
  };
})
