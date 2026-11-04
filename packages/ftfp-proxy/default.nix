{ lib
, stdenv
, fetchFromGitHub
, pkg-config
, glib
, gusb
, libfprint-tod
}:

# Upstream forgot to commit meson.build, so the four targets are built by hand.
stdenv.mkDerivation {
  pname = "ftfp-proxy";
  version = "0-unstable-2026-02-25";

  src = fetchFromGitHub {
    owner = "pccr10001";
    repo = "ftfp_proxy";
    rev = "cfa218eca25f557e3b258571cd532426b2e8e60e";
    hash = "sha256-MYn52DuUmr9RrY80RGuja0ZHkFF2T0gBIfKzYoT73e0=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ glib gusb libfprint-tod ];

  buildPhase = ''
    runHook preBuild
    CFLAGS="-O2 -fPIC -Wall -Iinclude -Isrc"
    $CC $CFLAGS -c src/client_lib.c src/ipc_common.c
    $CC $CFLAGS $(pkg-config --cflags gio-2.0) \
      -o ftfp_proxy_daemon src/daemon_main.c src/vendor_bridge.c ipc_common.o \
      $(pkg-config --libs gio-2.0) -ldl -lpthread
    $CC $CFLAGS -o ftfp_proxyctl src/ftfp_proxyctl.c client_lib.o ipc_common.o
    $CC $CFLAGS -shared $(pkg-config --cflags libfprint-2-tod-1 libfprint-2 gusb) \
      -o libdevice-focaltech-ftfp_proxy-tod-driver.so src/tod_ftfp_proxy_driver.c \
      client_lib.o ipc_common.o $(pkg-config --libs libfprint-2-tod-1 gio-2.0)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin ftfp_proxy_daemon ftfp_proxyctl
    install -Dm755 -t $out/lib/libfprint-2/tod-1 libdevice-focaltech-ftfp_proxy-tod-driver.so
    runHook postInstall
  '';

  passthru.driverPath = "/lib/libfprint-2/tod-1";

  meta = {
    description = "libfprint-tod driver that runs FocalTech's vendor libfprint in a separate daemon";
    homepage = "https://github.com/pccr10001/ftfp_proxy";
    platforms = lib.platforms.linux;
    mainProgram = "ftfp_proxyctl";
  };
}
