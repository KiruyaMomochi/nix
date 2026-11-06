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

  # KWin 6.8 drops input-method-v1 key requests without a keyboard grab, so
  # the lock screen keyboard typed nothing. Send keysyms instead.
  patches = [ ./lockscreen-keysym.patch ];

  # On unlock KWin closes the lock screen keyboard's connection, sometimes
  # while it is creating its compositor; the expect then aborts with a core
  # dump. Exit like the other disconnect paths do.
  #
  # saren uses skvirt on the desktop and this only on the lock screen, where
  # skvirt can't draw. manual_mode = true keeps it from popping on the
  # desktop; make manual mode not apply in lock screen mode.
  postPatch = ''
    substituteInPlace fcitx5-osk/src/state.rs --replace-fail \
      '    pub fn active_manual_mode(&self) -> bool {
        self.session_manual_mode()' \
      '    pub fn active_manual_mode(&self) -> bool {
        if self.window_manager.mode() == WindowManagerMode::KwinLockScreen {
            return false;
        }
        self.session_manual_mode()'
    f=$cargoDepsCopy/source-registry-0/iced_tiny_skia-0.14.0/src/window/compositor.rs
    chmod u+w $f
    substituteInPlace $f --replace-fail \
      '.expect("Create softbuffer context");' \
      '.unwrap_or_else(|e| { eprintln!("Create softbuffer context: {e}"); std::process::exit(1) });'
    f=$cargoDepsCopy/source-registry-0/iced_layershell-0.16.0/src/multi_window.rs
    chmod u+w $f
    substituteInPlace $f --replace-fail \
      '.expect("Cannot create compositer");' \
      '.unwrap_or_else(|e| { eprintln!("Cannot create compositor: {e}"); std::process::exit(1) });'
  '';

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
