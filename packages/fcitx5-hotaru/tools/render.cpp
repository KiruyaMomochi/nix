// Draws the keyboard to a PNG, for looking at it without a lock screen.
// usage: render out.png [idle|composing|symbols|english] [pressed-key-index]
#include <cstdlib>
#include <cstring>
#include <string>
#include "../src/keyboard.h"

int main(int argc, char **argv) {
    const int w = 1706, h = 500;
    const std::string mode = argc > 2 ? argv[2] : "idle";
    const auto theme = hotaru::Theme::load();
    hotaru::Keyboard kb;
    kb.setFont(theme.font);
    kb.resize(w, h);
    kb.setLanguage(mode != "english", "汉字");
    kb.setHints(true);
    if (mode == "composing") {
        kb.setCandidates({"ni hao", {"你好", "妳好", "拟好", "你", "尼", "泥"},
                          false, true});
    } else if (mode == "symbols") {
        kb.release(3 * 16); // the layer key
    }
    if (argc > 3) {
        kb.setPressed(std::atoi(argv[3]));
    }
    auto *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w * 2, h * 2);
    auto *cr = cairo_create(surface);
    cairo_scale(cr, 2, 2);
    kb.paint(cr, theme);
    cairo_surface_write_to_png(surface, argc > 1 ? argv[1] : "keyboard.png");
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
}
