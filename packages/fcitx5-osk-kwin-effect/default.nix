{ lib
, stdenv
, fetchFromGitHub
, cmake
, kdePackages
}:
# The upstream "experimental" KWin effect: shows fcitx5-osk when a touch
# lands within 200 ms of KWin's virtual keyboard turning active, so tapping
# a text field pops the keyboard while mouse clicks don't. Built against the
# exact kwin in the closure, so it is rebuilt whenever kwin changes.
stdenv.mkDerivation {
  pname = "fcitx5-osk-kwin-effect";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "fortime";
    repo = "fcitx5-osk";
    rev = "76a33b65b1c72519788c09cfb9f94c1df0f61949"; # 0.2.1
    hash = "sha256-g1klvPXGWMZlxVZHEP8JPQT6P1I260vvqU4npyLP4cQ=";
  };

  sourceRoot = "source/fcitx5-osk-kwin-launcher/kwin-plugin";

  # Upstream only builds this directory via add_subdirectory from the top
  # level, so it has no cmake_minimum_required/project of its own.
  postPatch = ''
    sed -i '1i cmake_minimum_required(VERSION 3.20)\nproject(fcitx5osk-kwin-effect LANGUAGES CXX)' CMakeLists.txt
  '';

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
  ];
  buildInputs = [
    kdePackages.kwin
    kdePackages.kcmutils
    kdePackages.kconfig
    kdePackages.ki18n
    kdePackages.qtbase
  ];
  dontWrapQtApps = true;

  meta = {
    description = "KWin effect that shows fcitx5-osk on touch";
    homepage = "https://github.com/fortime/fcitx5-osk";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
