{ lib
, stdenv
, fetchFromGitHub
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

  rustToolchain = fenix.fromToolchainName {
    name = rustToolchainChannel;
    sha256 = toolchainHash;
  };

  toolchainWithComponents = (rustToolchain.withComponents [
    "cargo"
    "rustc"
    "rust-src"
    "rustfmt"
    "clippy"
    "llvm-tools"
  ]);

  rustPlatform = makeRustPlatform {
    cargo = toolchainWithComponents;
    rustc = toolchainWithComponents;
  };

  otelArrowSrc = fetchFromGitHub {
    owner = "GreptimeTeam";
    repo = "otel-arrow";
    rev = "5da284414e9b14f678344b51e5292229e4b5f8d2";
    fetchSubmodules = true;
    hash = "sha256-rUf1jE/StIwWPaqiXyzU4rM7fXu4t5VgKNfIaq3M0V0=";
  };
in
rustPlatform.buildRustPackage rec {
  pname = "greptimedb";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "GreptimeTeam";
    repo = "greptimedb";
    rev = "v${version}";
    # nix-prefetch-url --unpack https://github.com/GreptimeTeam/greptimedb/archive/v1.0.2.tar.gz
    hash = "sha256-LMow1zgC2gr568XBrkliPaNrsw9ayoGf3JktQKkiG2I=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    # Hashes for git+https dependencies; obtained by setting to fakeHash and
    # letting nix tell us the correct value on first build.
    outputHashes = {
      "datafusion-52.1.0" = "sha256-JdEsP6swxG0lq2q6/YEWsImFBs8dfveGghlMw/QT6xU=";
      "greptime-proto-0.1.0" = "sha256-DRBUPazYDWxkf8mDbjbsGD5CpcqkaDcR2avd/5onU4w=";
      "loki-proto-0.1.0" = "sha256-/gmWsSllSe+CLppEIy1wdF6sB7a0TxjssZY3yyP+3SM=";
      "meter-core-0.1.0" = "sha256-E2lvqsfY5nEKgXcHAubzNKcZveX8VI0GMT9OSRvIFgs=";
      "opensrv-mysql-0.8.0" = "sha256-6Zq58c2tFFdMP8ZNYelXde53RGATrCex7Pj0ZCqulAc=";
      # Required even though we redirect via [patch] in postPatch — buildRustPackage
      # still parses Cargo.lock and demands a hash for every git source listed there.
      "otel-arrow-rust-0.1.0" = "sha256-rUf1jE/StIwWPaqiXyzU4rM7fXu4t5VgKNfIaq3M0V0=";
      "rskafka-0.6.0" = "sha256-RU4DN7BASu0VrUVWsfDrBqW6YXm0iuLzr7yUR/xSq7Y=";
      "sqlness-0.6.1" = "sha256-jRMBA/5T/Yh8TtTfTu36hmisdQIT7A5Ujabnd3CQTng=";
      "sqlparser-0.61.0" = "sha256-688CTiC+isSqm+EQRuFemaXxS/5QaB4/jIG539oOMds=";
      "uddsketch-0.1.0" = "sha256-VEub0vUF3w7U5LZsmBueegHNiuAE6jSgyo+x5r1C4h8=";
      "influxdb_line_protocol-0.1.0" = "sha256-RvPS4erQDrMxzPbZu8gT4g5q9UHMaq9DS5P0kb0UhD4=";
      "memcomparable-0.2.0" = "sha256-qZ+6pytEsg4m5SYzAcQAu1HMFzdkH7rQwEI+Cxzd8K8=";
    };
  };

  nativeBuildInputs = [
    pkg-config
    protobuf
    cmake
    clang
    mold
    perl
    # build.rs in common-version reads git metadata; provide a clean fallback.
    rustfmt
  ];

  buildInputs = [
    openssl
    zlib
    zstd
    libgit2
  ];

  # Build only the main greptime binary to keep build time/memory in check.
  cargoBuildFlags = [ "--bin" "greptime" ];

  postPatch = ''
    cat >> Cargo.toml <<'EOF'

    [patch."https://github.com/GreptimeTeam/otel-arrow"]
    otel-arrow-rust = { path = "${otelArrowSrc}/rust/otel-arrow-rust" }
    otlp-derive = { path = "${otelArrowSrc}/rust/otel-arrow-rust/src/pdata/otlp/derive" }
    otlp-model = { path = "${otelArrowSrc}/rust/otel-arrow-rust/src/pdata/otlp/model" }
    EOF
  '';

  # Tests require network/external services (kafka, etc.) — skip during build.
  doCheck = false;

  # jemalloc's mremap probe trips fortify hardening on Nix; upstream also
  # disables it. See https://github.com/tikv/jemallocator/issues/108
  hardeningDisable = [ "fortify" ];

  env = {
    # protoc location for tonic-build / prost-build.
    PROTOC = "${protobuf}/bin/protoc";
    # zstd-sys uses pkg-config when available.
    ZSTD_SYS_USE_PKG_CONFIG = "1";
    # Speed up link step on this large workspace.
    RUSTFLAGS = "-C link-arg=-fuse-ld=mold";
    # Inject reproducible build metadata so common-version's build.rs
    # does not try to invoke git inside the sandbox.
    GREPTIMEDB_BUILD_INFO_VERSION = version;
    GREPTIMEDB_BUILD_INFO_BRANCH = "main";
    GREPTIMEDB_BUILD_INFO_COMMIT = "unknown";
    GREPTIMEDB_BUILD_INFO_COMMIT_SHORT = "unknown";
    GREPTIMEDB_BUILD_INFO_DIRTY = "false";
  };

  # The build script for `common-version` shells out to `git`; without one
  # available in PATH it falls back to env vars above (see crate's build.rs).
  preBuild = ''
    # Avoid noisy panics if a build.rs tries to invoke `git rev-parse` etc.
    export HOME=$TMPDIR
    # `common-version`'s build.rs links against system libgit2; make the
    # shared library findable when the build script runs inside the sandbox.
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ libgit2 zlib zstd openssl stdenv.cc.cc.lib ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  meta = with lib; {
    description = "Open-source unified time-series database for metrics, logs, and traces";
    homepage = "https://github.com/GreptimeTeam/greptimedb";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "greptime";
    # Heavy 71-crate workspace; needs ~30+ min to build from scratch.
  };
}
