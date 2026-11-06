{
  lib,
  stdenv,
  cmake,
  pkg-config,
  wayland-scanner,
  fcitx5,
  wayland,
  wayland-protocols,
  cairo,
  pango,
}:
stdenv.mkDerivation {
  pname = "fcitx5-hotaru";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  nativeBuildInputs = [ cmake pkg-config wayland-scanner ];
  buildInputs = [ fcitx5 wayland wayland-protocols cairo pango ];
  cmakeFlags = [ "-DFCITX5_SOURCE=${fcitx5.src}" ];

  meta = {
    description = "fcitx5 addon: on-screen keyboard for the KDE lock screen";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
}
