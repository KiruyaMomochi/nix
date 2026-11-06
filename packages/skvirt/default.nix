{ lib
, stdenv
, fetchFromGitHub
, cmake
, pkg-config
, kdePackages
, hunspell
, hunspellDicts
, libime
, boost
, fcitx5
, xorgproto
, xkeyboard_config
}:
stdenv.mkDerivation {
  pname = "skvirt";
  version = "0-unstable-2026-11-05";

  src = fetchFromGitHub {
    owner = "Vendetta1871";
    repo = "skvirt";
    rev = "58360bb939f91e6d266e7b193271d5f5c46aad93";
    hash = "sha256-ROtZWKMj+PEuxGpa/nPzNuu/ReP/8YIZOrcw7FVZIT0=";
  };

  nativeBuildInputs = [ cmake pkg-config kdePackages.wrapQtAppsHook ];
  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.qtmultimedia
    kdePackages.qtwayland
    kdePackages.layer-shell-qt
    kdePackages.kconfig
    kdePackages.kcoreaddons
    kdePackages.ki18n
    kdePackages.kcmutils
    kdePackages.kirigami
    hunspell
    libime
    boost
    fcitx5
  ];

  cmakeFlags = [ "-DKDE_INSTALL_PLUGINDIR=${kdePackages.qtbase.qtPluginPrefix}" ];

  postPatch = ''
    substituteInPlace src/LayoutGenerator.cpp \
      --replace-fail /usr/include/X11/keysymdef.h ${xorgproto}/include/X11/keysymdef.h \
      --replace-fail /usr/share/X11/xkb/symbols/ ${xkeyboard_config}/share/X11/xkb/symbols/
    substituteInPlace src/SuggestionEngine.cpp \
      --replace-fail /usr/share/libime/sc.dict ${libime}/share/libime/sc.dict \
      --replace-fail /usr/lib/libime/zh_CN.lm ${libime}/lib/libime/zh_CN.lm \
      --replace-fail /usr/share/hunspell ${hunspellDicts.en_US}/share/hunspell \
      --replace-fail /usr/share/myspell /run/current-system/sw/share/hunspell \
      --replace-fail /usr/local/share/hunspell /run/current-system/sw/share/myspell
    substituteInPlace skvirt.desktop \
      --replace-fail /home/sweetclit/Projects/skvirt/build/skvirt skvirt \
      --replace-fail NoDisplay=true NoDisplay=false
  '';

  # Upstream's install target only installs the KCM, not the application.
  postInstall = ''
    install -Dm755 skvirt $out/bin/skvirt
    install -Dm644 ../skvirt.desktop $out/share/applications/skvirt.desktop
    install -Dm644 ../src/skvirt.kcfg $out/share/config.kcfg/skvirt.kcfg
  '';

  meta = {
    description = "Touch-driven KDE Wayland on-screen keyboard using uinput alongside Fcitx 5";
    homepage = "https://github.com/Vendetta1871/skvirt";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "skvirt";
  };
}
