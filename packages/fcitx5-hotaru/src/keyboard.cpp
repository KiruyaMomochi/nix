#include "keyboard.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <map>

namespace hotaru {
namespace {

constexpr uint32_t Return = 0xff0d;
constexpr uint32_t Left = 0xff51;
constexpr uint32_t Right = 0xff53;
constexpr int RowStride = 16;
// Keys in the strip above the letters.
constexpr int BarBase = 1000;

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

Color faded(Color c, double a) {
    c.a = a;
    return c;
}

// 小鶴雙拼: the final each letter stands for, or the initial for u/i/v.
const std::map<char, const char *> &flypyFinals() {
    static const std::map<char, const char *> finals = {
        {'q', "iu"},  {'w', "ei"},  {'e', "e"},    {'r', "uan"}, {'t', "ue"},
        {'y', "un"},  {'u', "sh"},  {'i', "ch"},   {'o', "uo"},  {'p', "ie"},
        {'a', "a"},   {'s', "ong"}, {'d', "ai"},   {'f', "en"},  {'g', "eng"},
        {'h', "ang"}, {'j', "an"},  {'k', "ing"},  {'l', "iang"}, {'z', "ou"},
        {'x', "ia"},  {'c', "ao"},  {'v', "zh"},   {'b', "in"},  {'n', "iao"},
        {'m', "ian"},
    };
    return finals;
}

void strokeRound(cairo_t *cr, const Color &color) {
    cairo_set_line_width(cr, 2);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    setColor(cr, color);
    cairo_stroke(cr);
}

} // namespace

Keyboard::Keyboard() {
    auto shift = Key{KeyKind::Shift, "⇧", 1.5};
    auto back = Key{KeyKind::Backspace, "⌫", 1.5};
    auto enter = Key{KeyKind::Enter, "⏎", 1.5};
    auto space = Key{KeyKind::Space, "", 4};
    auto lang = Key{KeyKind::Lang, ""};
    auto comma = Key{KeyKind::Char, ","};
    auto dot = Key{KeyKind::Char, "."};

    using Row = std::vector<Key>;
    // Letters on the left, a number pad on the right: the screen is wide,
    // and the lock screen password is digits.
    auto pad = [](std::vector<Key> keys) {
        for (auto &k : keys) {
            k.pad = true;
        }
        return keys;
    };
    const Row pad1 = pad(chars("123")), pad2 = pad(chars("456")),
              pad3 = pad(chars("789"));
    const Row pad4 = pad(Row{Key{KeyKind::Backspace, "⌫"},
                             Key{KeyKind::Char, "0"},
                             Key{KeyKind::Enter, "⏎"}});
    letters_ = {
        concat(chars("qwertyuiop"), pad1),
        concat(chars("asdfghjkl"), pad2),
        concat(concat(concat(Row{shift}, chars("zxcvbnm")), Row{back}), pad3),
        concat(Row{Key{KeyKind::Layer, "#+=", 1.5}, lang, comma, space, dot,
                   enter},
               pad4),
    };
    symbolRows_ = {
        concat(chars("!@#$%^&*()"), pad1),
        concat(chars("-_=+[]{}\\|"), pad2),
        concat(chars("`~;:'\"<>/?"), pad3),
        concat(Row{Key{KeyKind::Layer, "ABC", 1.5}, lang, comma, space, dot,
                   enter},
               pad4),
    };
}

std::vector<std::vector<Key>> &Keyboard::rows() {
    return symbols_ ? symbolRows_ : letters_;
}

const std::vector<std::vector<Key>> &Keyboard::rows() const {
    return symbols_ ? symbolRows_ : letters_;
}

void Keyboard::resize(double width, double height) {
    width_ = width;
    height_ = height;
    const double edge = 4;
    const double inner = width - 2 * edge;
    // A strip for candidates and tools, then four rows of keys.
    barH_ = std::round((height - 2 * edge) * 0.17);
    const double top = edge + barH_;
    // Ten letter units, a gap, three number pad units.
    letterUnit_ = inner * 0.70 / 10;
    const double padUnit = inner * 0.27 / 3;
    const double padX = edge + inner - 3 * padUnit;
    const double rowH = (height - edge - top) / letters_.size();
    for (auto *layer : {&letters_, &symbolRows_}) {
        for (size_t r = 0; r < layer->size(); r++) {
            auto &row = (*layer)[r];
            double units = 0;
            for (const auto &k : row) {
                units += k.pad ? 0 : k.width;
            }
            // Short letter rows sit centred, like the home row on a real
            // keyboard.
            double x = edge + (10 - units) * letterUnit_ / 2;
            double px = padX;
            for (auto &k : row) {
                auto &at = k.pad ? px : x;
                k.x = at;
                k.y = top + r * rowH;
                k.w = k.width * (k.pad ? padUnit : letterUnit_);
                k.h = rowH;
                at += k.w;
            }
        }
    }
    layoutBar();
}

double Keyboard::textWidth(const std::string &text, double size) const {
    auto *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    auto *cr = cairo_create(surface);
    auto *layout = pango_cairo_create_layout(cr);
    auto *font = pango_font_description_new();
    pango_font_description_set_family(font, font_.c_str());
    pango_font_description_set_absolute_size(font, size * PANGO_SCALE);
    pango_layout_set_font_description(layout, font);
    pango_layout_set_text(layout, text.c_str(), -1);
    int w, h;
    pango_layout_get_pixel_size(layout, &w, &h);
    pango_font_description_free(font);
    g_object_unref(layout);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return w;
}

bool Keyboard::composing() const {
    return !candidates_.words.empty() || !candidates_.preedit.empty();
}

void Keyboard::layoutBar() {
    bar_.clear();
    if (width_ <= 0) {
        return;
    }
    const double edge = 4;
    const double y = edge, h = barH_;
    const double tool = h * 1.3;
    double right = width_ - edge;
    auto add = [&](KeyKind kind, std::string label, double x, double w,
                   int index = 0) {
        Key k{kind, std::move(label)};
        k.x = x;
        k.y = y;
        k.w = w;
        k.h = h;
        k.index = index;
        bar_.push_back(std::move(k));
    };

    if (composing()) {
        // Candidates, left to right; the arrows page through them.
        if (candidates_.hasPrev || candidates_.hasNext) {
            right -= tool;
            add(KeyKind::NextPage, "", right, tool);
            right -= tool;
            add(KeyKind::PrevPage, "", right, tool);
        }
        const double padding = h * 0.45;
        // The preedit sits on the left, small, as rime spells it out.
        double x = edge;
        if (!candidates_.preedit.empty()) {
            x += textWidth(candidates_.preedit, h * 0.32) + padding * 2;
        }
        for (size_t i = 0; i < candidates_.words.size(); i++) {
            const double w =
                std::max(textWidth(candidates_.words[i], h * 0.48) +
                             padding * 2,
                         h * 1.4);
            if (x + w > right) {
                break;
            }
            add(KeyKind::Candidate, candidates_.words[i], x, w, i);
            x += w;
        }
        return;
    }

    // Idle: tools. Hiding keeps the corner Gboard and Windows give it.
    right -= tool;
    add(KeyKind::Hide, "", right, tool);
    if (!scriptLabel_.empty()) {
        const double w = std::max(textWidth(scriptLabel_, h * 0.4) + h, tool);
        right -= w;
        add(KeyKind::Script, scriptLabel_, right, w);
    }
}

void Keyboard::setCandidates(Candidates candidates) {
    candidates_ = std::move(candidates);
    if (pressed_ >= BarBase) {
        pressed_ = -1;
    }
    layoutBar();
}

void Keyboard::setLanguage(bool chinese, std::string scriptLabel) {
    chinese_ = chinese;
    scriptLabel_ = std::move(scriptLabel);
    layoutBar();
}

void Keyboard::setFont(std::string font) {
    font_ = std::move(font);
    layoutBar();
}

const Key *Keyboard::find(int key) const {
    if (key < 0) {
        return nullptr;
    }
    if (key >= BarBase) {
        size_t i = key - BarBase;
        return i < bar_.size() ? &bar_[i] : nullptr;
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
    if (rs.empty()) {
        return -1;
    }
    if (y < rs[0][0].y) {
        // The strip: only what's drawn there is a key.
        for (size_t i = 0; i < bar_.size(); i++) {
            const auto &k = bar_[i];
            if (x >= k.x && x < k.x + k.w) {
                return BarBase + i;
            }
        }
        return -1;
    }
    size_t r = 0;
    while (r + 1 < rs.size() && y >= rs[r + 1][0].y) {
        r++;
    }
    // The key under the finger, or the closest one: gaps, including the one
    // between letters and the number pad, belong to a neighbour.
    int best = -1;
    double bestDistance = 0;
    for (size_t c = 0; c < rs[r].size(); c++) {
        const auto &k = rs[r][c];
        const double d = std::max({k.x - x, x - (k.x + k.w), 0.0});
        if (best < 0 || d < bestDistance) {
            best = c;
            bestDistance = d;
        }
    }
    return r * RowStride + best;
}

std::string Keyboard::label(const Key &key) const {
    if (key.kind == KeyKind::Lang) {
        return chinese_ ? "中" : "EN";
    }
    if (key.kind == KeyKind::Char && chinese_ && !key.pad) {
        // rime turns these into full-width punctuation.
        if (key.label == ",") {
            return "，";
        }
        if (key.label == ".") {
            return "。";
        }
    }
    if (key.kind == KeyKind::Char && shift_ != Shift::Off && !symbols_ &&
        !key.pad) {
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

bool Keyboard::isSpace(int key) const {
    const auto *k = find(key);
    return k && k->kind == KeyKind::Space;
}

std::vector<uint32_t> Keyboard::dragSpace(double x) {
    if (!dragging_) {
        dragging_ = true;
        dragOrigin_ = x;
        dragMoved_ = false;
        return {};
    }
    // One character per half a letter key, like Gboard's space bar.
    const double step = letterUnit_ * 0.5;
    std::vector<uint32_t> syms;
    while (x - dragOrigin_ >= step) {
        syms.push_back(Right);
        dragOrigin_ += step;
    }
    while (dragOrigin_ - x >= step) {
        syms.push_back(Left);
        dragOrigin_ -= step;
    }
    if (!syms.empty()) {
        dragMoved_ = true;
    }
    return syms;
}

Keyboard::Action Keyboard::release(int key) {
    pressed_ = -1;
    const bool dragged = dragging_ && dragMoved_;
    dragging_ = dragMoved_ = false;
    const auto *k = find(key);
    Action a;
    if (!k) {
        return a;
    }
    switch (k->kind) {
    case KeyKind::Char: {
        // Send the key itself, not what's printed on it: rime decides
        // whether ',' becomes '，'.
        auto s = k->label;
        if (shift_ != Shift::Off && !symbols_ && !k->pad) {
            std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        }
        if (shift_ == Shift::Once) {
            shift_ = Shift::Off;
        }
        a.sym = static_cast<unsigned char>(s[0]);
        break;
    }
    case KeyKind::Space:
        // A drag moved the cursor instead.
        a.sym = dragged ? 0 : ' ';
        break;
    case KeyKind::Enter:
        a.sym = Return;
        break;
    case KeyKind::Backspace:
        // Sent on press, and repeated while held.
        break;
    case KeyKind::Shift: {
        auto now = nowMs();
        if (shift_ == Shift::Once && now - lastShiftTap_ < 350) {
            shift_ = Shift::Locked;
        } else {
            shift_ = shift_ == Shift::Off ? Shift::Once : Shift::Off;
        }
        lastShiftTap_ = now;
        break;
    }
    case KeyKind::Hide:
        a.hide = true;
        break;
    case KeyKind::Layer:
        symbols_ = !symbols_;
        break;
    case KeyKind::Lang:
        a.toggleLanguage = true;
        break;
    case KeyKind::Script:
        a.toggleScript = true;
        break;
    case KeyKind::Candidate:
        a.candidate = k->index;
        break;
    case KeyKind::PrevPage:
        a.page = -1;
        break;
    case KeyKind::NextPage:
        a.page = 1;
        break;
    }
    return a;
}

void Keyboard::reset() {
    symbols_ = false;
    shift_ = Shift::Off;
    pressed_ = -1;
    dragging_ = dragMoved_ = false;
}

void Keyboard::paintBar(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                        PangoFontDescription *font) const {
    const double edge = 4;
    auto showText = [&](const std::string &text, double size, double x,
                        double y, double w, double h, const Color &color,
                        bool centre) {
        pango_font_description_set_absolute_size(font, size * PANGO_SCALE);
        pango_layout_set_font_description(layout, font);
        pango_layout_set_text(layout, text.c_str(), -1);
        int tw, th;
        pango_layout_get_pixel_size(layout, &tw, &th);
        setColor(cr, color);
        cairo_move_to(cr, centre ? x + (w - tw) / 2 : x, y + (h - th) / 2);
        pango_cairo_show_layout(cr, layout);
    };

    if (composing() && !candidates_.preedit.empty()) {
        showText(candidates_.preedit, barH_ * 0.32, edge + barH_ * 0.45, edge,
                 0, barH_, faded(theme.text, 0.55), false);
    }

    for (size_t i = 0; i < bar_.size(); i++) {
        const auto &k = bar_[i];
        if (pressed_ == int(BarBase + i)) {
            // The look of a selected candidate in fcitx's plasma theme.
            roundedRect(cr, k.x + 2, k.y + 2, k.w - 4, k.h - 4, 5);
            setColor(cr, mix(theme.background, theme.accent, 0.3));
            cairo_fill_preserve(cr);
            setColor(cr, theme.accent);
            cairo_set_line_width(cr, 1.5);
            cairo_stroke(cr);
        }
        const double cx = k.x + k.w / 2, cy = k.y + k.h / 2;
        const double r = k.h * 0.12;
        switch (k.kind) {
        case KeyKind::Candidate:
            // The first is what space would pick.
            showText(k.label, barH_ * 0.48, k.x, k.y, k.w, k.h,
                     k.index == 0 ? theme.accent : theme.text, true);
            if (i + 1 < bar_.size() &&
                bar_[i + 1].kind == KeyKind::Candidate) {
                setColor(cr, faded(theme.text, 0.12));
                cairo_rectangle(cr, k.x + k.w - 0.5, k.y + k.h * 0.3, 1,
                                k.h * 0.4);
                cairo_fill(cr);
            }
            break;
        case KeyKind::PrevPage:
        case KeyKind::NextPage: {
            const bool enabled = k.kind == KeyKind::PrevPage
                                     ? candidates_.hasPrev
                                     : candidates_.hasNext;
            const double dx = k.kind == KeyKind::PrevPage ? 1 : -1;
            cairo_move_to(cr, cx + r * 0.6 * dx, cy - r * 1.4);
            cairo_line_to(cr, cx - r * 0.8 * dx, cy);
            cairo_line_to(cr, cx + r * 0.6 * dx, cy + r * 1.4);
            strokeRound(cr, faded(theme.text, enabled ? 1 : 0.25));
            break;
        }
        case KeyKind::Hide:
            cairo_move_to(cr, cx - r * 1.4, cy - r * 0.6);
            cairo_line_to(cr, cx, cy + r * 0.8);
            cairo_line_to(cr, cx + r * 1.4, cy - r * 0.6);
            strokeRound(cr, theme.text);
            break;
        case KeyKind::Script:
            showText(k.label, barH_ * 0.4, k.x, k.y, k.w, k.h,
                     faded(theme.text, 0.8), true);
            break;
        default:
            break;
        }
    }
}

void Keyboard::paint(cairo_t *cr, const Theme &theme) const {
    setColor(cr, theme.background);
    cairo_paint(cr);

    const auto &rs = rows();
    const double gap = 3;
    const double radius = 5;
    auto *layout = pango_cairo_create_layout(cr);
    auto *font = pango_font_description_new();
    pango_font_description_set_family(font, theme.font.c_str());

    paintBar(cr, theme, layout, font);

    auto drawText = [&](const std::string &text, double size, double x,
                        double y, double w, double h, const Color &color) {
        pango_font_description_set_absolute_size(font, size * PANGO_SCALE);
        pango_layout_set_font_description(layout, font);
        pango_layout_set_text(layout, text.c_str(), -1);
        int tw, th;
        pango_layout_get_pixel_size(layout, &tw, &th);
        setColor(cr, color);
        cairo_move_to(cr, x + (w - tw) / 2, y + (h - th) / 2);
        pango_cairo_show_layout(cr, layout);
    };

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
            // Only the number pad's Enter is green: it's the one that
            // unlocks.
            const bool green = k.kind == KeyKind::Enter && k.pad;
            if (green) {
                fill = down ? mix(theme.accent, theme.text, 0.15)
                            : theme.accent;
            } else if (lit) {
                fill = mix(fill, theme.accent, locked ? 0.6 : 0.3);
            }
            roundedRect(cr, k.x + gap, k.y + gap, k.w - 2 * gap,
                        k.h - 2 * gap, radius);
            setColor(cr, fill);
            if (lit && !green) {
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
            const bool small = (text.size() > 3 && k.kind == KeyKind::Layer) ||
                               k.kind == KeyKind::Lang;
            drawText(text, k.h * (small ? 0.30 : 0.46), k.x, k.y, k.w, k.h,
                     theme.text);

            if (hints_ && chinese_ && !symbols_ && !k.pad &&
                k.kind == KeyKind::Char) {
                auto it = flypyFinals().find(k.label[0]);
                if (it != flypyFinals().end()) {
                    // Top right corner, small and faint.
                    pango_font_description_set_absolute_size(
                        font, k.h * 0.2 * PANGO_SCALE);
                    pango_layout_set_font_description(layout, font);
                    pango_layout_set_text(layout, it->second, -1);
                    int tw, th;
                    pango_layout_get_pixel_size(layout, &tw, &th);
                    setColor(cr, faded(theme.text, 0.45));
                    cairo_move_to(cr, k.x + k.w - gap - tw - 4,
                                  k.y + gap + 2);
                    pango_cairo_show_layout(cr, layout);
                }
            }
        }
    }
    pango_font_description_free(font);
    g_object_unref(layout);
}

} // namespace hotaru
