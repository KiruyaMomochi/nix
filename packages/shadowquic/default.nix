{ lib
, rustPlatform
, fetchFromGitHub
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "shadowquic";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "spongebob888";
    repo = "shadowquic";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bS0KGYQMH8TGeEnxob9N7nKlvXwNfXL5YZxqiDeDITg=";
  };

  cargoHash = "sha256-wDRMAk96BWwsxiQDqxpQJxa58ijykCbOIenrt6rq0Ek=";

  # workspace default-members = [ "shadowquic" ]
  cargoBuildFlags = [ "-p" "shadowquic" ];
  doCheck = false;

  meta = {
    description = "0-RTT QUIC proxy with SNI camouflage (JLS)";
    homepage = "https://github.com/spongebob888/shadowquic";
    license = lib.licenses.mit;
    mainProgram = "shadowquic";
  };
})
