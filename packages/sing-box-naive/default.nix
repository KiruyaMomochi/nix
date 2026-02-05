{
  lib,
  sing-box,
  kyaru,
  makeWrapper,
  fetchFromGitHub,
}:

sing-box.overrideAttrs (
  final: old: {
    pname = "sing-box-naive";

    version = "1.13.0-rc.2";
    src = fetchFromGitHub {
      owner = "SagerNet";
      repo = "sing-box";
      rev = "refs/tags/v${final.version}";
      hash = "sha256-v/b0NO29JkSf2TfwIwg7XMCoQjXm9U/i5EA9o/NLaZ8=";
    };

    tags = (old.tags or [ ]) ++ [
      "with_naive"
      "with_naive_outbound"
    ];

    # New tags might change dependencies, so we need a new vendorHash.
    # Set to fake hash to trigger mismatch error and get the correct one.
    # vendorHash = "sha256-Qj2+1Lht6lEEC1ve/hTZiE/NhJwf0KKiFqr1FfDxjsQ=";
    vendorHash = "sha256-TxprnkoRtDtLxRgSRlwbODFHCQrwF5IhNegavm74/4k=";

    buildInputs = (old.buildInputs or [ ]) ++ [ kyaru.libcronet-naive ];

    env = (old.env or { }) // {
      CGO_CFLAGS = "-I${kyaru.libcronet-naive}/include";
      CGO_LDFLAGS = "-L${kyaru.libcronet-naive}/lib -lcronet";
      CGO_ENABLED = "1";
    };

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

    modPostBuild = ''
      echo "Patching vendored cronet-go..."
      # Make vendor directory writable
      chmod -R u+w vendor

      # Remove incompatible vendored static libraries (optional, but cleaner)
      find vendor/github.com/sagernet/cronet-go -name "*.a" -delete

      # Patch CGO directives in vendored files to use dynamic linking (-lcronet)
      # and remove hardcoded search paths so it uses our CGO_LDFLAGS
      find vendor/github.com/sagernet/cronet-go -name "*.go" -type f -print0 | xargs -0 sed -i \
        -e 's/-l:libcronet.a/-lcronet/g' \
        -e 's|-L\''${SRCDIR}/lib/[^ ]* ||g'
    '';

    # Use wrapper instead of patchelf to avoid binary corruption
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/sing-box \
        --prefix LD_LIBRARY_PATH : "${kyaru.libcronet-naive}/lib"
    '';
  }
)
