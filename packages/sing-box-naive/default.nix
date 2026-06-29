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

    version = "1.13.14";
    src = fetchFromGitHub {
      owner = "SagerNet";
      repo = "sing-box";
      rev = "refs/tags/v${final.version}";
      hash = "sha256-ODQ1i2lOuQLb3LDq6ONqHJQ7sT7dXICCJoyW/I9zF38=";
    };

    tags = (old.tags or [ ]) ++ [
      "with_naive"
      "with_naive_outbound"
    ];

    # New tags might change dependencies, so we need a new vendorHash.
    # Set to fake hash to trigger mismatch error and get the correct one.
    vendorHash = "sha256-VDaiyxnSCWyWZ68Yru4P2PyGx7DI2OhwV3SOWi+NlFA=";

    # cronet-go commit was force-pushed on GitHub; the old pseudo-version
    # is unresolvable via direct git fetch but still cached on Go module proxy.
    # Use overrideModAttrs to inject GOPROXY fix into the go-modules FOD.
    proxyVendor = true;
    env = (old.env or { }) // {
      CGO_CFLAGS = "-I${kyaru.libcronet-naive}/include";
      CGO_LDFLAGS = "-L${kyaru.libcronet-naive}/lib -lcronet";
      CGO_ENABLED = "1";
    };

    patches = (old.patches or [ ]) ++ [ ./json-log-format.patch ];

    # preBuild runs in BOTH the go-modules FOD and the main build.
    # - FOD phase: strip ",direct" from GOPROXY for force-pushed module resolution
    # - Main build phase: patch cronet-go cgo directives to use our dynamic lib
    preBuild = ''
      export GOPROXY="''${GOPROXY:-https://proxy.golang.org}"
      GOPROXY="$(echo "$GOPROXY" | sed 's/,direct//g')"
      case "$GOPROXY" in
        *proxy.golang.org*) ;;
        *) GOPROXY="$GOPROXY,https://proxy.golang.org" ;;
      esac
      export GOPROXY
      echo "sing-box-naive: GOPROXY=$GOPROXY"

      # Patch cronet-go cgo directives in mod cache (proxyVendor uses mod cache, not vendor/)
      # go build unpacks modules from $goModules into $GOPATH/pkg/mod/ during build,
      # so we pre-populate and patch them here (after configurePhase sets GOPATH).
      echo "Pre-populating mod cache from $goModules..."
      go mod download 2>/dev/null || true
      cronet_base="$GOPATH/pkg/mod/github.com/sagernet"
      if [ -d "$cronet_base" ]; then
        chmod -R u+w "$cronet_base"
        find "$cronet_base" -path "*cronet-go*" -name "*.a" -delete
        find "$cronet_base" -path "*cronet-go*" -name "*.go" -type f -print0 | xargs -0 sed -i \
          -e 's/-l:libcronet.a/-lcronet/g' \
          -e 's|-L\''${SRCDIR}/lib/[^ ]* ||g'
        echo "Patched cronet-go cgo directives in mod cache"
      else
        echo "WARNING: $cronet_base not found after go mod download"
      fi
    '';

    buildInputs = (old.buildInputs or [ ]) ++ [ kyaru.libcronet-naive ];

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

    # modPostBuild: with proxyVendor=true there's no vendor/ dir in the FOD,
    # mod cache patching is handled in preBuild above.
    modPostBuild = "";

    # Use wrapper instead of patchelf to avoid binary corruption
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/sing-box \
        --prefix LD_LIBRARY_PATH : "${kyaru.libcronet-naive}/lib"
    '';
  }
)
