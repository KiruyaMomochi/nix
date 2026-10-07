{ lib
, rustPlatform
, fetchFromGitHub
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "shadowquic";
  version = "0.3.13";

  src = fetchFromGitHub {
    owner = "spongebob888";
    repo = "shadowquic";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/EhbUtahn6/IXZKF5CgWifYI2fDB9elPE3C16B1oMOM=";
  };

  cargoHash = "sha256-usHhuwpQ/ERiu4Eo7Fv1l8UmLH7jkETQMAvnSfyHlvg=";

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
