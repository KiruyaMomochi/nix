{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "slbounce";
  version = "5";
  src = fetchurl {
    url = "https://github.com/TravMurav/slbounce/releases/download/v5/slbounce.efi";
    hash = "sha256-lsiaBqE5ueOc759SiWoaLIzVQ30P7u+ypcfqWzVhThc=";
  };
  sltest = fetchurl {
    url = "https://github.com/TravMurav/slbounce/releases/download/v5/sltest.efi";
    hash = "sha256-nUGuRiLbtcCigPSzNR9CKFzPmOZcZ0r+NxD85667GI0=";
  };
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm444 $src $out/share/efi/slbounceaa64.efi
    install -Dm444 $sltest $out/share/efi/sltestaa64.efi
    runHook postInstall
  '';
  meta = {
    description = "Qualcomm Secure Launch EL2 trampoline (upstream v5 EFI binaries, unsigned)";
    homepage = "https://github.com/TravMurav/slbounce";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
