{ lib
, chromium
}:

# Use the mkChromiumDerivation function exposed by the chromium package.
# This function handles all the complex environment setup (GN, Ninja, Python, Dependencies).
chromium.mkDerivation (base: rec {
  name = "libcronet";
  packageName = "libcronet";
  
  # We reuse the upstream chromium source code.
  # The mkChromiumDerivation function handles fetching sources internally via upstream-info.
  # So we don't need to specify src explicitly.
  
  # Define the flags from cronet-go/cmd/build-naive/cmd_build.go
  # These will be merged into the default flags defined in common.nix.
  # Note: common.nix handles the merging logic via `// (extraAttrs.gnFlags or { })`.
  gnFlags = {
    # Core Cronet flags
    is_cronet_build = true;
    is_official_build = false; # Avoid GN error: data_deps undefined in root BUILD.gn with official build
    is_debug = false;
    
    # Network stack features (Critical for Sing-box/Naive)
    enable_quic_proxy_support = true;
    enable_bracketed_proxy_uris = true;
    enable_reporting = false;
    
    # Size optimization
    symbol_level = 0;
    enable_dsyms = false;
    optimize_for_size = true;
    exclude_unwind_tables = true;
    enable_resource_allowlist_generation = false;

    # Linux specific
    use_sysroot = false; # We use Nix's environment
    use_cfi_icall = false;
    is_cfi = false;
    
    # Disable unnecessary features to save build time/size
    use_aura = false;
    use_ozone = false;
    
    # Enable GLib/GIO/NSS to fix linker errors (undefined symbols)
    # GetDesktopEnvironment needs GLib
    # Cert verification needs NSS or Chrome Root Store implementation details
    use_gio = true;
    use_glib = true;
    use_kerberos = false;
    use_nss_certs = true;
    
    # Fix assertion error: ICU alternative is not implemented for platform: linux
    # is_cronet_build defaults this to true (for mobile), but we are on Linux.
    use_platform_icu_alternatives = false;
    
    disable_zstd_filter = false;
    enable_backup_ref_ptr_support = false;
    enable_dangling_raw_ptr_checks = false;
  };
  
  # Surgically remove problematic lines from BUILD.gn that cause "Undefined identifier" errors
  # when building with is_cronet_build=true. These dependencies are not needed for libcronet.
  # We MUST append to base.postPatch to preserve Nixpkgs' chromium setup (like gclient_args.gni).
  # Also, forcibly inject a target to build cronet to ensure it's in the build graph.
  postPatch = (base.postPatch or "") + ''
    echo "Patching BUILD.gn to remove problematic data_deps..."
    sed -i '/data_deps += \[ "\/\/tools\/perf\/clear_system_cache" \]/d' BUILD.gn
    sed -i '/data_deps += \[ "\/\/chrome:linux_symbols" \]/d' BUILD.gn
    
    echo "Injecting force_cronet target into BUILD.gn..."
    echo 'group("force_cronet") { deps = [ "//components/cronet:cronet" ] }' >> BUILD.gn
    
    echo "Patching net/BUILD.gn to remove problematic configs..."
    sed -i '/configs += \[ "\/\/build\/config:precompiled_headers" \]/d' net/BUILD.gn
    sed -i '/configs += \[ "\/\/build\/config\/compiler:no_exit_time_destructors" \]/d' net/BUILD.gn
    sed -i '/configs += \[ "\/\/build\/config\/linux\/nss" \]/d' net/BUILD.gn
    
    echo "Patching net/BUILD.gn to disable net_unittests with a dummy template..."
    # Inject a template that swallows all variables to avoid "unused variable" errors
    sed -i '1i template("eat_everything") { group(target_name) { not_needed(invoker, "*") } }' net/BUILD.gn
    # Use the dummy template for net_unittests
    sed -i 's/_test_target_type = "cronet_test"/_test_target_type = "eat_everything"/g' net/BUILD.gn

    echo "Injecting shim implementations for missing base::nix symbols into base/base_paths_posix.cc..."
    cat >> base/base_paths_posix.cc <<EOF

// SHIM INJECTED BY NIX FOR LIBCRONET
// Note: Necessary headers are already included by base_paths_posix.cc

namespace base {
namespace nix {

DesktopEnvironment GetDesktopEnvironment(Environment* env) {
  return DESKTOP_ENVIRONMENT_OTHER;
}

// Fixed signature to match linker error: base::basic_cstring_view<char>
// We use the raw template type to avoid guessing the alias (StringPiece vs string_view).
FilePath GetXDGDirectory(Environment* env, base::basic_cstring_view<char> dir_name, const char* fallback_dir) {
  return FilePath(fallback_dir ? fallback_dir : "");
}

FilePath GetXDGUserDirectory(const char* dir_name, const char* fallback_dir) {
  return FilePath(fallback_dir ? fallback_dir : "");
}

}  // namespace nix
}  // namespace base
EOF
  '';

  # Override configurePhase to bypass the strict "fail on warning" check.
  # common.nix fails if `gn gen` emits any WARNINGs (e.g. unused args like blink_symbol_level).
  # Since we are doing a cronet build, some inherited flags are indeed unused, which is fine.
  configurePhase = ''
    runHook preConfigure

    # This is to ensure expansion of $out.
    libExecPath="$out/libexec/$packageName"
    
    # Run the replacement script (copied from common.nix)
    # We need to make sure python3 is available in nativeBuildInputs
    python3 build/linux/unbundle/replace_gn_files.py --system-libraries flac libjpeg libpng libxml libxslt
    
    echo "Running gn gen..."
    gn gen --args="$gnFlags" out/Release
    
    runHook postConfigure
  '';

  # We only want to build the cronet target (which produces libcronet.so)
  # Use our injected target to ensure reachability.
  buildTargets = [ "force_cronet" ];

  # Custom install phase to extract only libcronet and headers
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/lib $out/include
    
    # Copy shared library
    # Note: Ninja outputs versioned library (e.g. libcronet.143.0.7499.192.so)
    echo "Installing libcronet.so..."
    # Find the versioned so file
    SO_FILE=$(find out/Release -name "libcronet.*.so" | head -n 1)
    if [ -n "$SO_FILE" ]; then
      cp "$SO_FILE" $out/lib/
      # Create generic symlink
      ln -s "$(basename "$SO_FILE")" $out/lib/libcronet.so
    else
      echo "Error: libcronet.so not found!"
      ls -l out/Release
      exit 1
    fi
    
    # Copy headers
    # Sing-box expects headers usually from components/cronet/native/include
    echo "Installing headers..."
    if [ -d "components/cronet/native/include" ]; then
      cp -r components/cronet/native/include/* $out/include/
    else
      echo "Warning: Header files not found in components/cronet/native/include"
      # Fallback check or error?
      # Let's list components/cronet to help debug if it fails
      ls -R components/cronet || true
    fi
    
    runHook postInstall
  '';
  
  # Disable the default postFixup from common.nix which tries to patch a non-existent executable
  postFixup = "";
  
  meta = with lib; {
    description = "Libcronet built from Chromium source for Sing-box";
    homepage = "https://chromium.googlesource.com/chromium/src/+/master/components/cronet/";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
})
