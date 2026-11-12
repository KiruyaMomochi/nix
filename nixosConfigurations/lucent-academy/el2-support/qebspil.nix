{
  lib,
  stdenv,
  fetchFromGitHub,
}:
let
  gnuEfi = fetchFromGitHub {
    owner = "ncroxon";
    repo = "gnu-efi";
    rev = "1fee8ab566ce91b9cbab9f2c85db96566d79063b";
    sha256 = "1alfszs5ccvwgbdshxq5777icmz4w4w4vggff174xi9qsrlg9250";
  };
  dtc = fetchFromGitHub {
    owner = "dgibson";
    repo = "dtc";
    rev = "2d10aa2afe35527728db30b35ec491ecb6959e5c";
    sha256 = "01jl27909gpbkn8pnlpny44qsfjzg0m8ysbs83gsqxsnyypb7419";
  };
in
stdenv.mkDerivation {
  pname = "qebspil";
  version = "1-8e4d9e6-qmp";
  src = fetchFromGitHub {
    owner = "stephan-gh";
    repo = "qebspil";
    rev = "8e4d9e676a3b3afe136cda9b953a2139ff1a32d0";
    sha256 = "1ds9sbdgsz1wzidfhg7k6xim2jqpg8y2x51xqykwdaszmdkz12wg";
  };
  # Exact gitlink revisions from this source tree, fetched via tarballs rather
  # than network-dependent recursive git clones (dtc's upstream is kernel.org).
  postUnpack = ''
    cp -r ${gnuEfi}/. "$sourceRoot/external/gnu-efi/"
    cp -r ${dtc}/. "$sourceRoot/external/dtc/"
    chmod -R u+w "$sourceRoot/external"
  '';
  patches = [ ./qebspil-qmp.patch ];
  strictDeps = true;
  hardeningDisable = [ "all" ];
  dontConfigure = true;
  makeFlags = [
    "ARCH=aarch64"
    "QEBSPIL_ALWAYS_START=0"
  ];
  installPhase = ''
    runHook preInstall
    install -Dm444 out/qebspilaa64.efi $out/share/efi/qebspilaa64.efi
    runHook postInstall
  '';
  dontStrip = true;
  meta = {
    description = "Qualcomm EFI DSP loader with AOSS QMP load_state sequencing";
    homepage = "https://github.com/stephan-gh/qebspil";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
