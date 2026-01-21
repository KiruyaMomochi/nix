{ lib
, sing-box
, kyaru
, makeWrapper
, fetchFromGitHub
, buildGoModule
}:

# (sing-box.override {
#   buildGoModule = args: (buildGoModule ((lib.fix args) // {
#     vendorHash = "";
#   }));
# })
sing-box.overrideAttrs (final: old: {
  pname = "sing-box-naive";

  version = "1.13.0-unstable-2026-01-22";
  src = fetchFromGitHub {
    owner = "SagerNet";
    repo = "sing-box";
    rev = "60a1e4c86600385257a9c0b4f4c1899fe6edde7b";
    hash = "sha256-lp6xg0OqdrxpBFt5SFIJZggkseusZKODRbWcDOooZBE=";
  };

  tags = (old.tags or [ ]) ++ [ "with_naive" "with_naive_outbound" ];

  # New tags might change dependencies, so we need a new vendorHash.
  # Set to fake hash to trigger mismatch error and get the correct one.
  vendorHash = "sha256-jeUlj7K8Kl2cTH3IinWIaNrPM/cgX6Qeu28XNi75bFU=";
  # vendorHash = "sha256-rs5Jxj75qU47zEH0gbYy0/QUSq3sektaITcefg2Qb78=";

  buildInputs = (old.buildInputs or [ ]) ++ [ kyaru.libcronet-naive ];

  env = (old.env or { }) // {
    CGO_CFLAGS = "-I${kyaru.libcronet-naive}/include";
    CGO_LDFLAGS = "-L${kyaru.libcronet-naive}/lib -lcronet";
    CGO_ENABLED = "1";
  };

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  preBuild = ''
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
})
