{ lib
, stdenv
, fetchFromGitLab
, cmake
, pkg-config
, ghostty
, libghostty-vt
, zig_0_17
, kdePackages
}:
let
  # nixpkgs' libghostty-vt is pinned to a pre-1.4 commit that lacks the
  # search/image/animation APIs Kwi checks for; build it from ghostty's 1.4 tree.
  ghostty-vt = (libghostty-vt.override { zig_0_16 = zig_0_17; }).overrideAttrs (old: {
    version = ghostty.version;
    src = ghostty.src;
    deps = ghostty.deps;
  });
in
stdenv.mkDerivation {
  pname = "kwi";
  version = "0.1.0-unstable-2026-11-06";

  src = fetchFromGitLab {
    domain = "invent.kde.org";
    owner = "utilities";
    repo = "kwi";
    rev = "61e6e7f78a78c9fa59e86b8c5d583588792dd5ee";
    hash = "sha256-hAIJsTmqe0EIOPyQFT8ukim4SCBpXITyEH2r6z7rRbA=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
    kdePackages.qtshadertools
  ];

  buildInputs = (with kdePackages; [
    qtbase
    qtdeclarative
    qtsvg
    kcoreaddons
    kconfig
    kdbusaddons
    kguiaddons
    ki18n
    kirigami
    kpty
    kio
    knotifications
    kwindowsystem
    kparts
    kxmlgui
    kwidgetsaddons
    kirigami-addons
    kirigami-app-components
    kitemmodels
    qqc2-desktop-style
  ]) ++ [ ghostty-vt ];

  cmakeFlags = [ (lib.cmakeBool "BUILD_TESTING" false) ];

  passthru.libghostty-vt = ghostty-vt;

  meta = {
    description = "Modern and fast terminal for KDE Plasma, built on libghostty-vt";
    homepage = "https://invent.kde.org/utilities/kwi";
    license = with lib.licenses; [ gpl2Only gpl3Only lgpl21Only lgpl3Only ];
    mainProgram = "kwi";
    platforms = lib.platforms.linux;
  };
}
