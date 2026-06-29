{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, makeRustPlatform
, fenix
, pkg-config
, protobuf
, cmake
, clang
, mold
, perl
, openssl
, zlib
, zstd
, libgit2
, rustfmt
}:

let
  # Pin to the exact nightly the upstream rust-toolchain.toml requires.
  # Bump in lockstep with v${version}/rust-toolchain.toml.
  rustToolchainChannel = "nightly-2026-03-21";
  toolchainHash = "sha256-rboGKQLH4eDuiY01SINOqmXUFUNr9F4awoFZGzib17o=";

  # Downloads the official pre-built nightly toolchain via fenix.
  # Equivalent to `rustup toolchain install nightly-2026-03-21`.
  rustToolchain = fenix.fromToolchainName {
    name = rustToolchainChannel;
    sha256 = toolchainHash;
  };

  toolchainWithComponents = (rustToolchain.withComponents [
    "cargo"
    "rustc"
    "rust-src"      # needed by proc-macro / build.rs
    "rustfmt"       # some build.rs invoke rustfmt on generated code
    "clippy"
    "llvm-tools"    # coverage / profiling; harmless to include
  ]);

  # Construct a full rustPlatform (buildRustPackage, fetchCargoVendor, etc.)
  # using our pinned nightly toolchain.
  rustPlatform = makeRustPlatform {
    cargo = toolchainWithComponents;
    rustc = toolchainWithComponents;
  };

  # otel-arrow is a git dependency in Cargo.lock pointing to GitHub.
  # Pre-fetch the source and redirect via [patch] in postPatch since
  # the nix sandbox has no network access.
  otelArrowSrc = fetchFromGitHub {
    owner = "GreptimeTeam";
    repo = "otel-arrow";
    rev = "5da284414e9b14f678344b51e5292229e4b5f8d2";
    fetchSubmodules = true;
    hash = "sha256-rUf1jE/StIwWPaqiXyzU4rM7fXu4t5VgKNfIaq3M0V0=";
  };

  # Pre-built dashboard frontend assets. The build.rs fetches these from
  # GitHub when the "dashboard" feature is enabled, but the sandbox has
  # no network. We pre-fetch and extract in postPatch instead.
  dashboardVersion = "v0.12.2";
  dashboardAssets = fetchurl {
    url = "https://github.com/GreptimeTeam/dashboard/releases/download/${dashboardVersion}/build.tar.gz";
    hash = "sha256-NUdyKea962AWnltxt/tVgltQvjtZ6WXnI6pBfnuktzQ=";
  };
in
rustPlatform.buildRustPackage rec {
  pname = "greptimedb";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "GreptimeTeam";
    repo = "greptimedb";
    rev = "v${version}";
    hash = "sha256-srHhOQP4yxosuj+XxeyrpwhAiJO7MVETLzr/LuhbchM=";
  };

  # Single-FOD vendor of all dependencies (including git deps) via
  # fetchCargoVendor. To update: set to lib.fakeHash, build once,
  # nix reports the correct hash, paste it back.
  cargoHash = "sha256-pAwTI3OFGmkWM+A3wpHyCyO/h99/GiU0yLtOIdiyB/s=";

  nativeBuildInputs = [
    pkg-config   # lets *-sys crates find C library .pc files
    protobuf     # protoc for tonic-build / prost-build
    cmake        # build system for some C deps (e.g. zstd-sys)
    clang        # libclang for bindgen
    mold         # fast linker, replaces ld
    perl         # openssl-sys Configure script needs perl
    rustfmt      # some build.rs format generated code with rustfmt
  ];

  buildInputs = [
    openssl      # TLS (some crates still depend on openssl besides rustls)
    zlib         # compression
    zstd         # compression (zstd-sys)
    libgit2      # common-version build.rs reads git metadata
  ];

  # Only build the main binary; skip other bin targets (benchmarks, etc.)
  cargoBuildFlags = [ "--bin" "greptime" ];

  # Cargo features:
  #   servers/dashboard — embedded web dashboard (rust-embed bundles static assets)
  #   cmd/vector_index  — ANN vector index for semantic search on time-series data
  buildFeatures = [ "servers/dashboard" "cmd/vector_index" ];

  # 1. Redirect otel-arrow git dep to pre-fetched local source via [patch].
  # 2. Extract pre-downloaded dashboard assets to the path rust-embed expects
  #    (src/servers/dashboard/dist/) and patch out the network fetch in build.rs.
  postPatch = ''
    cat >> Cargo.toml <<'EOF'

    [patch."https://github.com/GreptimeTeam/otel-arrow"]
    otel-arrow-rust = { path = "${otelArrowSrc}/rust/otel-arrow-rust" }
    otlp-derive = { path = "${otelArrowSrc}/rust/otel-arrow-rust/src/pdata/otlp/derive" }
    otlp-model = { path = "${otelArrowSrc}/rust/otel-arrow-rust/src/pdata/otlp/model" }
    EOF

    # Inject pre-fetched dashboard assets and disable the network fetch.
    tar -xzf ${dashboardAssets} -C src/servers/dashboard/
    substituteInPlace src/servers/build.rs \
      --replace-fail 'fetch_dashboard_assets();' '{}; /* dashboard assets injected by nix */'
  '';

  # Tests require kafka, network, etc. — cannot run in sandbox.
  doCheck = false;

  # jemalloc's mremap probe trips nix fortify hardening.
  # Upstream tikv-jemallocator also recommends disabling it.
  hardeningDisable = [ "fortify" ];

  env = {
    PROTOC = "${protobuf}/bin/protoc";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
    # mold linker: cuts link phase from ~2min to ~15s on this 71-crate workspace.
    RUSTFLAGS = "-C link-arg=-fuse-ld=mold";
    # Inject build metadata so common-version's build.rs doesn't panic
    # when it can't find git inside the sandbox.
    GREPTIMEDB_BUILD_INFO_VERSION = version;
    GREPTIMEDB_BUILD_INFO_BRANCH = "main";
    GREPTIMEDB_BUILD_INFO_COMMIT = "unknown";
    GREPTIMEDB_BUILD_INFO_COMMIT_SHORT = "unknown";
    GREPTIMEDB_BUILD_INFO_DIRTY = "false";
  };

  preBuild = ''
    export HOME=$TMPDIR
    # Make shared libraries findable when build.rs runs inside the sandbox.
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ libgit2 zlib zstd openssl stdenv.cc.cc.lib ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  meta = with lib; {
    description = "Open-source unified time-series database for metrics, logs, and traces";
    homepage = "https://github.com/GreptimeTeam/greptimedb";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "greptime";
  };
}
