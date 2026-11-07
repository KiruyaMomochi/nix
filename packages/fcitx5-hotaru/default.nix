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
  gawk,
  unicode-emoji,
}:
stdenv.mkDerivation {
  pname = "fcitx5-hotaru";
  version = "0.2.0";
  src = lib.cleanSource ./.;

  nativeBuildInputs = [ cmake pkg-config wayland-scanner ];
  buildInputs = [ fcitx5 wayland wayland-protocols cairo pango ];
  cmakeFlags = [ "-DFCITX5_SOURCE=${fcitx5.src}" ];

  # The emoji page's list, from Unicode's own.
  postInstall = ''
    ${gawk}/bin/awk -f ${./tools/emoji.awk} \
      ${unicode-emoji}/share/unicode/emoji/emoji-test.txt \
      > $out/share/fcitx5/hotaru/emoji.txt
  '';

  meta = {
    description = "fcitx5 addon: on-screen keyboard";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
}
