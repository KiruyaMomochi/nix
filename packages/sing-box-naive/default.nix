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

    version = "1.13.13";
    src = fetchFromGitHub {
      owner = "SagerNet";
      repo = "sing-box";
      rev = "refs/tags/v${final.version}";
      hash = "sha256-RsiBxPQOE4rE3cFRjl81x1uIG2A4/smSBUg+G0vm7uQ=";
    };

    tags = (old.tags or [ ]) ++ [
      "with_naive"
      "with_naive_outbound"
    ];

    # New tags might change dependencies, so we need a new vendorHash.
    # Set to fake hash to trigger mismatch error and get the correct one.
    vendorHash = "sha256-BZrGw1/9QL4aj+bMV/kZq+iTCQdgf4A4GZ922vbW27Y=";

    # cronet-go commit was force-pushed on GitHub; the old pseudo-version
    # is unresolvable. Use Go module proxy for vendoring (required for FOD
    # network access) and replace the dead pseudo-version with current HEAD.
    proxyVendor = true;
    env = (old.env or { }) // {
      CGO_CFLAGS = "-I${kyaru.libcronet-naive}/include";
      CGO_LDFLAGS = "-L${kyaru.libcronet-naive}/lib -lcronet";
      CGO_ENABLED = "1";
    };

    patches = (old.patches or [ ]) ++ [ ./json-log-format.patch ];

    # The old cronet-go pseudo-version (2faf34666c2c) was force-pushed away.
    # Replace it with current HEAD and strip platform-specific lib submodules
    # we don't need (we build libcronet-naive ourselves as a shared library).
    prePatch = (old.prePatch or "") + ''
      echo "Fixing cronet-go pseudo-version (force-pushed commit)..."
      # Replace dead pseudo-version with current resolvable HEAD
      sed -i 's|github.com/sagernet/cronet-go v0.0.0-20260513071958-2faf34666c2c|github.com/sagernet/cronet-go v0.0.0-20260516034104-ec86c1492fc8|g' go.mod
      # Strip cronet-go/all and platform lib submodules (static .a we don't use)
      sed -i '/github\.com\/sagernet\/cronet-go\/all/d' go.mod go.sum
      sed -i '/github\.com\/sagernet\/cronet-go\/lib\//d' go.mod go.sum
      # Remove stale go.sum entries for old cronet-go version
      sed -i '/github\.com\/sagernet\/cronet-go v0.0.0-20260513071958/d' go.sum
    '';

    buildInputs = (old.buildInputs or [ ]) ++ [ kyaru.libcronet-naive ];

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

    modPostBuild = ''
      echo "Patching vendored cronet-go..."
      # Make vendor directory writable
      chmod -R u+w vendor

      if [ -d vendor/github.com/sagernet/cronet-go ]; then
        # Remove incompatible vendored static libraries (optional, but cleaner)
        find vendor/github.com/sagernet/cronet-go -name "*.a" -delete

        # Patch CGO directives in vendored files to use dynamic linking (-lcronet)
        # and remove hardcoded search paths so it uses our CGO_LDFLAGS
        find vendor/github.com/sagernet/cronet-go -name "*.go" -type f -print0 | xargs -0 sed -i \
          -e 's/-l:libcronet.a/-lcronet/g' \
          -e 's|-L\''${SRCDIR}/lib/[^ ]* ||g'
      else
        echo "cronet-go not in vendor (stripped from go.mod), skipping patches"
      fi
    '';

    # Use wrapper instead of patchelf to avoid binary corruption
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/sing-box \
        --prefix LD_LIBRARY_PATH : "${kyaru.libcronet-naive}/lib"
    '';
  }
)
