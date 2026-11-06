#pragma once

#include <string>

namespace hotaru {

struct Color {
    double r, g, b, a = 1.0;
};

// Colors come from the KDE color scheme, the same place fcitx's "plasma"
// classicui theme takes them from, so the keyboard matches the candidate
// window.
struct Theme {
    Color background{0.125, 0.137, 0.149};
    Color key{0.161, 0.173, 0.188};
    Color keyAlt{0.192, 0.212, 0.231};
    Color text{0.988, 0.988, 0.988};
    Color accent{0.239, 0.682, 0.914};
    std::string font = "Noto Sans";

    static Theme load();
};

} // namespace hotaru
