{
  lib,
  stdenv,
  systemd,
  meson,
  ninja,
  pkg-config,
  gperf,
  python3,
  libcap,
  util-linux,
  libxcrypt,
}:

# Only systemd-bootaa64.efi from the systemd we run, with ./systemd-boot-ignore-alt.patch.
# Building the whole systemd for one EFI binary would rebuild most of the system.
stdenv.mkDerivation {
  pname = "systemd-boot-vivobook-s15";
  inherit (systemd) version src;

  patches = [ ./systemd-boot-ignore-alt.patch ];

  # meson runs these at configure time; the sandbox has no /usr/bin/env.
  postPatch = "patchShebangs tools src/boot";

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gperf
    (python3.withPackages (p: [
      p.jinja2
      p.pyelftools
    ]))
  ];
  buildInputs = [
    libcap
    util-linux
    libxcrypt
  ];

  mesonAutoFeatures = "disabled";
  mesonFlags = [
    "-Dbootloader=enabled"
    "-Dmode=release"
    "-Dtests=false"
    "-Dman=disabled"
    "-Dhtml=disabled"
    # The sandbox has no /etc/os-release to detect these from; same values as nixpkgs' systemd.
    "-Dsbat-distro=nixos"
    "-Dsbat-distro-summary=NixOS"
    "-Dsbat-distro-url=https://nixos.org/"
    "-Dsbat-distro-pkgname=systemd"
    "-Dsbat-distro-version=${systemd.version}"
  ];

  ninjaFlags = [ "src/boot/systemd-bootaa64.efi" ];

  installPhase = ''
    runHook preInstall
    install -Dm644 src/boot/systemd-bootaa64.efi $out/systemd-bootaa64.efi
    runHook postInstall
  '';

  meta.platforms = [ "aarch64-linux" ];
}
