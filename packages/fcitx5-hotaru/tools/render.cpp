// Draws the keyboard to a PNG, for looking at it without a lock screen.
// usage: render out.png [pressed-key-index] [symbols]
#include <cstdlib>
#include <cstring>
#include "../src/keyboard.h"

int main(int argc, char **argv) {
    const int w = 1706, h = 426;
    hotaru::Keyboard kb;
    kb.resize(w, h);
    if (argc > 3 && std::strcmp(argv[3], "letters") == 0) {
        kb.release(4 * 16); // the layer key
    }
    if (argc > 2) {
        kb.setPressed(std::atoi(argv[2]));
    }
    auto *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w * 2, h * 2);
    auto *cr = cairo_create(surface);
    cairo_scale(cr, 2, 2);
    kb.paint(cr, hotaru::Theme::load());
    cairo_surface_write_to_png(surface, argc > 1 ? argv[1] : "keyboard.png");
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
}
