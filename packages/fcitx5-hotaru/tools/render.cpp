// Draws the keyboard to a PNG, for looking at it without a lock screen.
// usage: render out.png [idle|composing|symbols|english|password|menu] [pressed]
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
    if (const char *dir = std::getenv("HOTARU_DATA")) {
        hotaru::Keyboard::loadData(dir);
    }
    kb.resize(w, h);
    kb.setLanguage(mode != "english");
    kb.setPad(mode == "password");
    if (mode == "composing") {
        kb.setCandidates({"ni hao",
                          {"你好", "妳好", "拟好", "你", "尼", "泥", "呢",
                           "腻", "逆", "倪", "妮", "拟", "匿", "溺", "霓",
                           "你好啊", "尼泊尔", "泥巴", "逆天"},
                          0});
    } else if (mode == "symbols") {
        kb.release(3 * 16); // the layer key
    } else if (mode == "popup") {
        kb.setLanguage(true);
        // Holding the full stop, in the bottom row.
        kb.hold(1 * 16 + 6);
        kb.openPopup(1 * 16 + 6); // j
    } else if (mode == "lang") {
        kb.setInputMethods({"EN", "中", "酷", "あ"}, 1);
        kb.hold(3 * 16 + 1);
        kb.openPopup(3 * 16 + 1);
    } else if (mode == "emoji" || mode == "kaomoji") {
        // Nothing recent yet: opens on the first tab.
        kb.release(1000 + (mode == "emoji" ? 0 : 1));
    } else if (mode == "enter") {
        kb.hold(3 * 16 + 5);
        kb.openPopup(3 * 16 + 5);
        kb.popupMove(1e9, 0); // slid up into it
    } else if (mode == "zhuyin" || mode == "zhuyin-hold") {
        kb.setInputMethods({"EN", "中", "注", "あ"}, 2);
        kb.setZhuyin(true);
        kb.setCandidates({"ㄋㄧˇ ㄏㄠˇ",
                          {"你好", "妳好", "擬好", "你", "妳", "擬", "禰"},
                          0});
        if (mode == "zhuyin-hold") {
            kb.hold(1 * 16 + 5); // ㄗ
            kb.openPopup(1 * 16 + 5);
        }
    } else if (mode == "menu") {
        kb.setMenu({{"中文", true}, {"半角", false}, {"汉字", true},
                    {"。，", true}, {"小鹤双拼", true}, {"双拼提示", false}});
        kb.release(1002); // the menu button, left of hide
    }
    if (argc > 3) {
        kb.hold(std::atoi(argv[3]));
    }
    auto *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w * 2, h * 2);
    auto *cr = cairo_create(surface);
    cairo_scale(cr, 2, 2);
    kb.paint(cr, theme);
    cairo_surface_write_to_png(surface, argc > 1 ? argv[1] : "keyboard.png");
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
}
