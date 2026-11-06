#include "keyboard.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <pango/pangocairo.h>

namespace hotaru {
namespace {

constexpr uint32_t BackSpace = 0xff08;
constexpr uint32_t Return = 0xff0d;
constexpr int RowStride = 16;

std::vector<Key> chars(const std::string &s) {
    std::vector<Key> row;
    for (char c : s) {
        row.push_back({KeyKind::Char, std::string(1, c)});
    }
    return row;
}

std::vector<Key> concat(std::vector<Key> a, const std::vector<Key> &b) {
    a.insert(a.end(), b.begin(), b.end());
    return a;
}

uint64_t nowMs() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(
               steady_clock::now().time_since_epoch())
        .count();
}

void roundedRect(cairo_t *cr, double x, double y, double w, double h,
                 double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

void setColor(cairo_t *cr, const Color &c) {
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a);
}

Color mix(const Color &a, const Color &b, double t) {
    return {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t};
}

} // namespace

Keyboard::Keyboard() {
    auto shift = Key{KeyKind::Shift, "⇧", 1.5};
    auto back = Key{KeyKind::Backspace, "⌫", 1.5};
    auto enter = Key{KeyKind::Enter, "⏎", 1.5};
    auto space = Key{KeyKind::Space, "", 5};
    auto comma = Key{KeyKind::Char, ","};
    auto dot = Key{KeyKind::Char, "."};

    using Row = std::vector<Key>;
    letters_ = {
        chars("1234567890"),
        chars("qwertyuiop"),
        chars("asdfghjkl"),
        concat(concat(Row{shift}, chars("zxcvbnm")), Row{back}),
        Row{Key{KeyKind::Layer, "?123", 1.5}, comma, space, dot, enter},
    };
    // A phone-style number pad, centred under the password field; the lock
    // screen opens on this page.
    auto pad = [](const char *label) {
        return Key{KeyKind::Char, label, 1.7};
    };
    auto padKey = [](KeyKind kind, const char *label) {
        return Key{kind, label, 1.7};
    };
    numbers_ = {
        Row{pad("1"), pad("2"), pad("3")},
        Row{pad("4"), pad("5"), pad("6")},
        Row{pad("7"), pad("8"), pad("9")},
        Row{padKey(KeyKind::Backspace, "⌫"), pad("0"),
            padKey(KeyKind::Enter, "⏎")},
        Row{Key{KeyKind::Layer, "ABC", 5.1}},
    };
}

std::vector<std::vector<Key>> &Keyboard::rows() {
    return numberPad_ ? numbers_ : letters_;
}

const std::vector<std::vector<Key>> &Keyboard::rows() const {
    return numberPad_ ? numbers_ : letters_;
}

void Keyboard::resize(double width, double height) {
    width_ = width;
    height_ = height;
    const double pad = 4;
    // The digit row is a little shorter: passwords use it, but less than
    // the letters.
    for (auto *layer : {&letters_, &numbers_}) {
        // Letters: the digit row is a little shorter. Number pad: the ABC
        // strip at the bottom is.
        const bool letters = layer == &letters_;
        const double rowH = (height - 2 * pad) / (layer->size() - 0.4);
        double y = pad;
        for (size_t r = 0; r < layer->size(); r++) {
            const bool slim = letters ? r == 0 : r + 1 == layer->size();
            const double h = slim ? rowH * 0.6 : rowH;
            auto &row = (*layer)[r];
            double units = 0;
            for (const auto &k : row) {
                units += k.width;
            }
            // Every row is ten units wide; shorter rows sit centred, like
            // the home row on a real keyboard.
            const double unit = (width - 2 * pad) / 10;
            double x = pad + (10 - units) * unit / 2;
            for (auto &k : row) {
                k.x = x;
                k.y = y;
                k.w = k.width * unit;
                k.h = h;
                x += k.w;
            }
            y += h;
        }
    }
}

const Key *Keyboard::find(int key) const {
    if (key < 0) {
        return nullptr;
    }
    const auto &rs = rows();
    size_t r = key / RowStride, c = key % RowStride;
    if (r >= rs.size() || c >= rs[r].size()) {
        return nullptr;
    }
    return &rs[r][c];
}

int Keyboard::keyAt(double x, double y) const {
    const auto &rs = rows();
    if (rs.empty() || rs[0].empty()) {
        return -1;
    }
    size_t r = 0;
    while (r + 1 < rs.size() && y >= rs[r + 1][0].y) {
        r++;
    }
    const auto &row = rs[r];
    size_t c = 0;
    while (c + 1 < row.size() && x >= row[c + 1].x) {
        c++;
    }
    return r * RowStride + c;
}

std::string Keyboard::label(const Key &key) const {
    if (key.kind == KeyKind::Char && shift_ != Shift::Off && !numberPad_) {
        std::string s = key.label;
        std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        return s;
    }
    return key.label;
}

bool Keyboard::repeats(int key) const {
    const auto *k = find(key);
    return k && k->kind == KeyKind::Backspace;
}

std::optional<uint32_t> Keyboard::release(int key) {
    pressed_ = -1;
    const auto *k = find(key);
    if (!k) {
        return std::nullopt;
    }
    switch (k->kind) {
    case KeyKind::Char: {
        auto s = label(*k);
        if (shift_ == Shift::Once) {
            shift_ = Shift::Off;
        }
        return static_cast<uint32_t>(static_cast<unsigned char>(s[0]));
    }
    case KeyKind::Space:
        return ' ';
    case KeyKind::Enter:
        return Return;
    case KeyKind::Backspace:
        // Sent on press, and repeated while held.
        return std::nullopt;
    case KeyKind::Shift: {
        auto now = nowMs();
        if (shift_ == Shift::Once && now - lastShiftTap_ < 350) {
            shift_ = Shift::Locked;
        } else {
            shift_ = shift_ == Shift::Off ? Shift::Once : Shift::Off;
        }
        lastShiftTap_ = now;
        return std::nullopt;
    }
    case KeyKind::Layer:
        numberPad_ = !numberPad_;
        return std::nullopt;
    }
    return std::nullopt;
}

void Keyboard::reset() {
    numberPad_ = true;
    shift_ = Shift::Off;
    pressed_ = -1;
}

void Keyboard::paint(cairo_t *cr, const Theme &theme) const {
    // Labels are sized by the letter rows, so digits match letters.
    const double letterH = rows()[1][0].h;
    auto rowH = [letterH](const Key &) { return letterH; };
    setColor(cr, theme.background);
    cairo_paint(cr);

    const auto &rs = rows();
    const double gap = 3;
    const double radius = 5;
    auto *layout = pango_cairo_create_layout(cr);
    auto *font = pango_font_description_new();
    pango_font_description_set_family(font, theme.font.c_str());

    for (size_t r = 0; r < rs.size(); r++) {
        for (size_t c = 0; c < rs[r].size(); c++) {
            const auto &k = rs[r][c];
            const bool down = pressed_ == int(r * RowStride + c);
            const bool special = k.kind != KeyKind::Char &&
                                 k.kind != KeyKind::Space;
            Color fill = special ? theme.keyAlt : theme.key;
            // Pressed keys and an active shift look like the selected
            // candidate in fcitx's plasma theme: accent-tinted, outlined.
            const bool lit = down || (k.kind == KeyKind::Shift &&
                                      shift_ != Shift::Off);
            const bool locked = k.kind == KeyKind::Shift &&
                                shift_ == Shift::Locked;
            if (k.kind == KeyKind::Enter) {
                fill = down ? mix(theme.accent, theme.text, 0.15)
                            : theme.accent;
            } else if (lit) {
                fill = mix(fill, theme.accent, locked ? 0.6 : 0.3);
            }
            roundedRect(cr, k.x + gap, k.y + gap, k.w - 2 * gap,
                        k.h - 2 * gap, radius);
            setColor(cr, fill);
            if (lit && k.kind != KeyKind::Enter) {
                cairo_fill_preserve(cr);
                setColor(cr, theme.accent);
                cairo_set_line_width(cr, 1.5);
                cairo_stroke(cr);
            } else {
                cairo_fill(cr);
            }

            auto text = label(k);
            if (text.empty()) {
                continue;
            }
            const bool small = text.size() > 3 && k.kind == KeyKind::Layer;
            pango_font_description_set_absolute_size(
                font, rowH(k) * (small ? 0.30 : 0.46) * PANGO_SCALE);
            pango_layout_set_font_description(layout, font);
            pango_layout_set_text(layout, text.c_str(), -1);
            int tw, th;
            pango_layout_get_pixel_size(layout, &tw, &th);
            setColor(cr, theme.text);
            cairo_move_to(cr, k.x + (k.w - tw) / 2, k.y + (k.h - th) / 2);
            pango_cairo_show_layout(cr, layout);
        }
    }
    pango_font_description_free(font);
    g_object_unref(layout);
}

} // namespace hotaru
