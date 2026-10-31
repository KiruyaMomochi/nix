{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, makeWrapper
, openssl
, wayland
, libxkbcommon
, vulkan-loader
, libGL
, libX11
, libXcursor
, libXi
, libXrandr
, libxcb
, kdePackages
}:
rustPlatform.buildRustPackage rec {
  pname = "fcitx5-osk";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "fortime";
    repo = "fcitx5-osk";
    rev = "76a33b65b1c72519788c09cfb9f94c1df0f61949"; # 0.2.1
    hash = "sha256-g1klvPXGWMZlxVZHEP8JPQT6P1I260vvqU4npyLP4cQ=";
  };

  cargoHash = "sha256-Zx3wPuIrvWbLsMWtCP0efq1rLolVMS94xlKaaFqgJeA=";

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ openssl wayland libxkbcommon ];

  # The default CMake build only runs Cargo and installs these data files.
  # Keep installation prefix-relative, including the system D-Bus policy.
  postInstall = ''
    mkdir -p $out/share/{applications,dbus-1/services,dbus-1/system.d,icons/hicolor/scalable/apps,licenses/fcitx5-osk} \
      $out/lib/systemd/system $out/etc/xdg/fcitx5-osk/themes
    for file in pkg/share/applications/*.in pkg/share/dbus-1/services/*.in pkg/lib/systemd/system/*.in; do
      destination="$out/''${file#pkg/}"
      substitute "$file" "''${destination%.in}" --subst-var-by INSTALL_BIN_DIR "$out/bin"
    done
    cp pkg/share/dbus-1/system.d/*.conf $out/share/dbus-1/system.d/
    cp -r pkg/share/fcitx5-osk $out/share/
    mkdir -p $out/share/fcitx5-osk/examples
    cp -r assets/layouts assets/key_sets $out/share/fcitx5-osk/examples/
    cp assets/icons/fcitx5-osk.svg $out/share/icons/hicolor/scalable/apps/fyi.fortime.Fcitx5Osk.svg
    cp LICENSE $out/share/licenses/fcitx5-osk/
    ln -s $out/share/fcitx5-osk/themes/breeze-light.toml $out/etc/xdg/fcitx5-osk/themes/breeze-light.toml

    # iced/winit load graphics and window-system libraries dynamically.
    wrapProgram $out/bin/fcitx5-osk \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ wayland libxkbcommon vulkan-loader libGL libX11 libXcursor libXi libXrandr libxcb ]} \
      --prefix XDG_CONFIG_DIRS : "$out/etc/xdg"
    # The launcher uses D-Bus activation for the system's addon-enabled Fcitx,
    # and kreadconfig6/kwriteconfig6 to monitor and restart KWin's input method.
    wrapProgram $out/bin/fcitx5-osk-kwin-launcher \
      --prefix PATH : ${lib.makeBinPath [ kdePackages.kconfig ]}
  '';

  meta = {
    description = "On-screen keyboard for Fcitx 5 with a KWin Wayland launcher";
    homepage = "https://github.com/fortime/fcitx5-osk";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "fcitx5-osk";
  };
}
