#include "keyboard.h"

#include <array>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <cmath>
#include <map>

namespace hotaru {
namespace {

constexpr uint32_t Return = 0xff0d;
constexpr uint32_t Left = 0xff51;
constexpr uint32_t Right = 0xff53;
constexpr int RowStride = 16;
// Keys in the strip above the letters, and in the menu.
constexpr int BarBase = 1000;
constexpr int MenuBase = 2000;
constexpr int PickerBase = 3000;
constexpr int PickerRows = 3;
constexpr size_t RecentMax = 40;

struct Category {
    std::string tab;
    std::vector<std::string> items;
};
// [0] emoji, [1] kaomoji; tabs in the order the files give them.
std::vector<Category> &pickerData(int which) {
    static std::vector<Category> data[2];
    return data[which];
}
constexpr double Edge = 4;

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

// Line icons for the emoji tabs and the strip's emoji button, the way
// Gboard draws them: one colour, so they read as buttons beside the
// colour emoji they open. Named by the emoji the tab stands for; r is half
// the icon's size.
bool drawIcon(cairo_t *cr, const std::string &name, double cx, double cy,
              double r, const Color &color) {
    const double lw = std::max(1.5, r * 0.14);
    cairo_save(cr);
    cairo_set_line_width(cr, lw);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    setColor(cr, color);
    auto circle = [&](double x, double y, double radius) {
        cairo_new_sub_path(cr);
        cairo_arc(cr, x, y, radius, 0, 2 * M_PI);
    };
    auto dot = [&](double x, double y, double radius) {
        circle(x, y, radius);
        cairo_fill(cr);
    };
    bool known = true;
    if (name == "😀" || name == "😊") {
        circle(cx, cy, r * 0.9);
        cairo_stroke(cr);
        dot(cx - r * 0.32, cy - r * 0.2, r * 0.11);
        dot(cx + r * 0.32, cy - r * 0.2, r * 0.11);
        cairo_arc(cr, cx, cy + r * 0.05, r * 0.45, M_PI * 0.2, M_PI * 0.8);
        cairo_stroke(cr);
    } else if (name == "kaomoji") {
        // (・ω・), drawn: brackets, two dots, a small ω. The brackets reach
        // as high and low as the smiley's circle beside it.
        const double R = r * 1.3, a = 0.245 * M_PI;
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx + r * 0.2, cy, R, M_PI - a, M_PI + a);
        cairo_stroke(cr);
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx - r * 0.2, cy, R, -a, a);
        cairo_stroke(cr);
        dot(cx - r * 0.4, cy - r * 0.15, r * 0.12);
        dot(cx + r * 0.4, cy - r * 0.15, r * 0.12);
        cairo_new_sub_path(cr);
        cairo_arc_negative(cr, cx - r * 0.15, cy + r * 0.2, r * 0.15, M_PI,
                           0);
        cairo_arc_negative(cr, cx + r * 0.15, cy + r * 0.2, r * 0.15, M_PI,
                           0);
        cairo_stroke(cr);
    } else if (name == "🕘") {
        circle(cx, cy, r * 0.9);
        cairo_move_to(cr, cx, cy - r * 0.5);
        cairo_line_to(cr, cx, cy);
        cairo_line_to(cr, cx + r * 0.35, cy + r * 0.25);
        cairo_stroke(cr);
    } else if (name == "👋") {
        // A person: head and shoulders.
        circle(cx, cy - r * 0.38, r * 0.36);
        cairo_stroke(cr);
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx, cy + r * 0.9, r * 0.75, M_PI, 2 * M_PI);
        cairo_stroke(cr);
    } else if (name == "🐱") {
        cairo_move_to(cr, cx - r * 0.8, cy + r * 0.1);
        cairo_line_to(cr, cx - r * 0.75, cy - r * 0.8);
        cairo_line_to(cr, cx - r * 0.3, cy - r * 0.45);
        cairo_line_to(cr, cx + r * 0.3, cy - r * 0.45);
        cairo_line_to(cr, cx + r * 0.75, cy - r * 0.8);
        cairo_line_to(cr, cx + r * 0.8, cy + r * 0.1);
        cairo_curve_to(cr, cx + r * 0.8, cy + r * 0.95, cx - r * 0.8,
                       cy + r * 0.95, cx - r * 0.8, cy + r * 0.1);
        cairo_stroke(cr);
        dot(cx - r * 0.3, cy + r * 0.05, r * 0.09);
        dot(cx + r * 0.3, cy + r * 0.05, r * 0.09);
    } else if (name == "🍙") {
        cairo_move_to(cr, cx, cy - r * 0.85);
        cairo_curve_to(cr, cx + r * 0.3, cy - r * 0.85, cx + r * 0.95,
                       cy + r * 0.3, cx + r * 0.8, cy + r * 0.65);
        cairo_curve_to(cr, cx + r * 0.7, cy + r * 0.85, cx - r * 0.7,
                       cy + r * 0.85, cx - r * 0.8, cy + r * 0.65);
        cairo_curve_to(cr, cx - r * 0.95, cy + r * 0.3, cx - r * 0.3,
                       cy - r * 0.85, cx, cy - r * 0.85);
        cairo_stroke(cr);
        cairo_rectangle(cr, cx - r * 0.3, cy + r * 0.25, r * 0.6, r * 0.55);
        cairo_fill(cr);
    } else if (name == "🚗") {
        cairo_move_to(cr, cx - r * 0.9, cy + r * 0.35);
        cairo_line_to(cr, cx - r * 0.9, cy);
        cairo_line_to(cr, cx - r * 0.6, cy - r * 0.55);
        cairo_line_to(cr, cx + r * 0.6, cy - r * 0.55);
        cairo_line_to(cr, cx + r * 0.9, cy);
        cairo_line_to(cr, cx + r * 0.9, cy + r * 0.35);
        cairo_close_path(cr);
        cairo_stroke(cr);
        dot(cx - r * 0.5, cy + r * 0.45, r * 0.18);
        dot(cx + r * 0.5, cy + r * 0.45, r * 0.18);
    } else if (name == "⚽") {
        circle(cx, cy, r * 0.9);
        cairo_stroke(cr);
        // The seams of a tennis ball, simpler than a football's.
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx - r * 1.25, cy, r * 0.8, -M_PI / 4, M_PI / 4);
        cairo_stroke(cr);
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx + r * 1.25, cy, r * 0.8, M_PI * 0.75, M_PI * 1.25);
        cairo_stroke(cr);
    } else if (name == "💡") {
        cairo_new_sub_path(cr);
        cairo_arc(cr, cx, cy - r * 0.25, r * 0.6, M_PI * 0.8, M_PI * 2.2);
        cairo_line_to(cr, cx + r * 0.3, cy + r * 0.5);
        cairo_line_to(cr, cx - r * 0.3, cy + r * 0.5);
        cairo_close_path(cr);
        cairo_stroke(cr);
        cairo_move_to(cr, cx - r * 0.25, cy + r * 0.85);
        cairo_line_to(cr, cx + r * 0.25, cy + r * 0.85);
        cairo_stroke(cr);
    } else if (name == "❤️") {
        cairo_move_to(cr, cx, cy + r * 0.8);
        cairo_curve_to(cr, cx - r * 1.3, cy - r * 0.1, cx - r * 0.55,
                       cy - r * 1.05, cx, cy - r * 0.35);
        cairo_curve_to(cr, cx + r * 0.55, cy - r * 1.05, cx + r * 1.3,
                       cy - r * 0.1, cx, cy + r * 0.8);
        cairo_close_path(cr);
        cairo_stroke(cr);
    } else if (name == "🏳️") {
        cairo_move_to(cr, cx - r * 0.6, cy + r * 0.9);
        cairo_line_to(cr, cx - r * 0.6, cy - r * 0.85);
        cairo_curve_to(cr, cx - r * 0.1, cy - r * 1.05, cx + r * 0.2,
                       cy - r * 0.55, cx + r * 0.75, cy - r * 0.75);
        cairo_line_to(cr, cx + r * 0.75, cy + r * 0.1);
        cairo_curve_to(cr, cx + r * 0.2, cy + r * 0.3, cx - r * 0.1,
                       cy - r * 0.2, cx - r * 0.6, cy);
        cairo_stroke(cr);
    } else if (name == "␣") {
        cairo_move_to(cr, cx - r * 0.8, cy - r * 0.25);
        cairo_line_to(cr, cx - r * 0.8, cy + r * 0.3);
        cairo_line_to(cr, cx + r * 0.8, cy + r * 0.3);
        cairo_line_to(cr, cx + r * 0.8, cy - r * 0.25);
        cairo_stroke(cr);
    } else if (name == "▶") {
        // Drawn thin to sit with the ⌫ and ⏎ glyphs around it.
        cairo_move_to(cr, cx - r * 0.35, cy - r * 0.8);
        cairo_line_to(cr, cx + r * 0.45, cy);
        cairo_line_to(cr, cx - r * 0.35, cy + r * 0.8);
        cairo_stroke(cr);
    } else if (name == "newline") {
        // ⏎ folding back to the left, and under it the start of the line
        // it makes: enter, but staying in the box.
        cairo_move_to(cr, cx + r * 0.7, cy - r * 0.85);
        cairo_line_to(cr, cx + r * 0.7, cy - r * 0.1);
        cairo_line_to(cr, cx - r * 0.7, cy - r * 0.1);
        cairo_move_to(cr, cx - r * 0.35, cy - r * 0.45);
        cairo_line_to(cr, cx - r * 0.7, cy - r * 0.1);
        cairo_line_to(cr, cx - r * 0.35, cy + r * 0.25);
        cairo_move_to(cr, cx - r * 0.7, cy + r * 0.75);
        cairo_line_to(cr, cx + r * 0.05, cy + r * 0.75);
        cairo_stroke(cr);
    } else {
        known = false;
    }
    cairo_restore(cr);
    return known;
}

// Centre, left, up, right, down, as Gboard has them. Empty: nothing that way.
using FlickItems = std::array<const char *, 5>;
const FlickItems *flickItems(const std::string &label) {
    static const std::map<std::string, FlickItems> table = {
        {"あ", {"あ", "い", "う", "え", "お"}},
        {"か", {"か", "き", "く", "け", "こ"}},
        {"さ", {"さ", "し", "す", "せ", "そ"}},
        {"た", {"た", "ち", "つ", "て", "と"}},
        {"な", {"な", "に", "ぬ", "ね", "の"}},
        {"は", {"は", "ひ", "ふ", "へ", "ほ"}},
        {"ま", {"ま", "み", "む", "め", "も"}},
        {"や", {"や", "（", "ゆ", "）", "よ"}},
        {"ら", {"ら", "り", "る", "れ", "ろ"}},
        {"わ", {"わ", "を", "ん", "ー", ""}},
        {"、。", {"、", "。", "？", "！", "…"}},
        {"゛小", {"゛小", "゛", "", "゜", "小"}},
    };
    auto it = table.find(label);
    return it != table.end() ? &it->second : nullptr;
}

// How mozc is told each kana: it composes them from romaji itself.
std::string romajiOf(const std::string &kana) {
    static const std::map<std::string, std::string> table = {
        {"あ", "a"},   {"い", "i"},   {"う", "u"},   {"え", "e"},
        {"お", "o"},   {"か", "ka"},  {"き", "ki"},  {"く", "ku"},
        {"け", "ke"},  {"こ", "ko"},  {"さ", "sa"},  {"し", "si"},
        {"す", "su"},  {"せ", "se"},  {"そ", "so"},  {"た", "ta"},
        {"ち", "ti"},  {"つ", "tu"},  {"て", "te"},  {"と", "to"},
        {"な", "na"},  {"に", "ni"},  {"ぬ", "nu"},  {"ね", "ne"},
        {"の", "no"},  {"は", "ha"},  {"ひ", "hi"},  {"ふ", "hu"},
        {"へ", "he"},  {"ほ", "ho"},  {"ま", "ma"},  {"み", "mi"},
        {"む", "mu"},  {"め", "me"},  {"も", "mo"},  {"や", "ya"},
        {"ゆ", "yu"},  {"よ", "yo"},  {"ら", "ra"},  {"り", "ri"},
        {"る", "ru"},  {"れ", "re"},  {"ろ", "ro"},  {"わ", "wa"},
        {"を", "wo"},  {"ん", "nn"},  {"ー", "-"},   {"が", "ga"},
        {"ぎ", "gi"},  {"ぐ", "gu"},  {"げ", "ge"},  {"ご", "go"},
        {"ざ", "za"},  {"じ", "zi"},  {"ず", "zu"},  {"ぜ", "ze"},
        {"ぞ", "zo"},  {"だ", "da"},  {"ぢ", "di"},  {"づ", "du"},
        {"で", "de"},  {"ど", "do"},  {"ば", "ba"},  {"び", "bi"},
        {"ぶ", "bu"},  {"べ", "be"},  {"ぼ", "bo"},  {"ぱ", "pa"},
        {"ぴ", "pi"},  {"ぷ", "pu"},  {"ぺ", "pe"},  {"ぽ", "po"},
        {"ゔ", "vu"},  {"ぁ", "xa"},  {"ぃ", "xi"},  {"ぅ", "xu"},
        {"ぇ", "xe"},  {"ぉ", "xo"},  {"っ", "xtu"}, {"ゃ", "xya"},
        {"ゅ", "xyu"}, {"ょ", "xyo"}, {"ゎ", "xwa"}, {"、", ","},
        {"。", "."},   {"？", "?"},   {"！", "!"},   {"…", "z."},
        {"（", "("},   {"）", ")"},
    };
    auto it = table.find(kana);
    return it != table.end() ? it->second : std::string{};
}

// What ゛小 turns a kana into. which: 0 goes round its forms; 1 ゛, 2 ゜ and
// 3 small go to that form, or back if it's already there. "" for no such form.
std::string nextKanaForm(const std::string &kana, int which) {
    // Plain, ゛, ゜, small.
    static const std::array<const char *, 4> forms[] = {
        {"か", "が", "", ""},   {"き", "ぎ", "", ""},   {"く", "ぐ", "", ""},
        {"け", "げ", "", ""},   {"こ", "ご", "", ""},   {"さ", "ざ", "", ""},
        {"し", "じ", "", ""},   {"す", "ず", "", ""},   {"せ", "ぜ", "", ""},
        {"そ", "ぞ", "", ""},   {"た", "だ", "", ""},   {"ち", "ぢ", "", ""},
        {"つ", "づ", "", "っ"}, {"て", "で", "", ""},   {"と", "ど", "", ""},
        {"は", "ば", "ぱ", ""}, {"ひ", "び", "ぴ", ""}, {"ふ", "ぶ", "ぷ", ""},
        {"へ", "べ", "ぺ", ""}, {"ほ", "ぼ", "ぽ", ""}, {"あ", "", "", "ぁ"},
        {"い", "", "", "ぃ"},   {"う", "ゔ", "", "ぅ"}, {"え", "", "", "ぇ"},
        {"お", "", "", "ぉ"},   {"や", "", "", "ゃ"},   {"ゆ", "", "", "ゅ"},
        {"よ", "", "", "ょ"},   {"わ", "", "", "ゎ"},
    };
    for (const auto &row : forms) {
        if (std::find(row.begin(), row.end(), kana) == row.end()) {
            continue;
        }
        if (which > 0) {
            if (!*row[which]) {
                return {};
            }
            return kana == row[which] ? row[0] : row[which];
        }
        // Round: plain, small, ゛, ゜.
        std::vector<std::string> round;
        for (int form : {0, 3, 1, 2}) {
            if (*row[form]) {
                round.push_back(row[form]);
            }
        }
        const auto at = std::find(round.begin(), round.end(), kana);
        return round[(at - round.begin() + 1) % round.size()];
    }
    return {};
}

bool pinnedKey(const Key &k) {
    return k.kind == KeyKind::Layer || k.kind == KeyKind::Lang;
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
    // The letters stay for romaji. Where the number pad goes: the kana, and
    // Gboard's right-hand column with ⌫ at the top. Four narrower columns in
    // the three's width.
    kanaRows_ = letters_;
    const char *const kana[4][3] = {{"あ", "か", "さ"},
                                    {"た", "な", "は"},
                                    {"ま", "や", "ら"},
                                    {"゛小", "わ", "、。"}};
    const Key side[4] = {Key{KeyKind::Backspace, "⌫", 0.75, true},
                         Key{KeyKind::CursorRight, "▶", 0.75, true},
                         Key{KeyKind::Space, "␣", 0.75, true},
                         Key{KeyKind::Enter, "⏎", 0.75, true}};
    for (size_t r = 0; r < kanaRows_.size(); r++) {
        auto &row = kanaRows_[r];
        row.erase(std::remove_if(row.begin(), row.end(),
                                 [](const Key &k) { return k.pad; }),
                  row.end());
        for (const char *label : kana[r]) {
            row.push_back(Key{KeyKind::Char, label, 0.75, true});
        }
        row.push_back(side[r]);
    }
    // 大千, as Gboard lays it out: four rows of ten, ㄦ by the space bar,
    // no shift. Each key sends what rime's bopomofo schema reads as that
    // symbol, the key it sits on in 大千.
    auto zhuyin = [](const char *keys, const char *faces) {
        Row row;
        std::string f = faces;
        size_t at = 0;
        for (const char *k = keys; *k; k++) {
            Key key{KeyKind::Char, std::string(1, *k)};
            const size_t next = f.find(' ', at);
            key.face = f.substr(at, next - at);
            at = next == std::string::npos ? f.size() : next + 1;
            row.push_back(std::move(key));
        }
        return row;
    };
    auto er = Key{KeyKind::Char, "-"};
    er.face = "ㄦ";
    zhuyinRows_ = {
        zhuyin("1234567890", "ㄅ ㄉ ˇ ˋ ㄓ ˊ ˙ ㄚ ㄞ ㄢ"),
        zhuyin("qwertyuiop", "ㄆ ㄊ ㄍ ㄐ ㄔ ㄗ ㄧ ㄛ ㄟ ㄣ"),
        zhuyin("asdfghjkl;", "ㄇ ㄋ ㄎ ㄑ ㄕ ㄘ ㄨ ㄜ ㄠ ㄤ"),
        zhuyin("zxcvbnm,./", "ㄈ ㄌ ㄏ ㄒ ㄖ ㄙ ㄩ ㄝ ㄡ ㄥ"),
        // , and . are ㄝ and ㄡ here, so the comma key puts in ， itself.
        Row{Key{KeyKind::Layer, "#+=", 1.5}, lang, Key{KeyKind::Char, "，"},
            space, er, back, enter},
    };
}

void Keyboard::loadData(const std::string &dir) {
    const char *files[2] = {"/emoji.txt", "/kaomoji.txt"};
    for (int which = 0; which < 2; which++) {
        auto &data = pickerData(which);
        if (!data.empty()) {
            continue;
        }
        FILE *f = std::fopen((dir + files[which]).c_str(), "r");
        if (!f) {
            continue;
        }
        char *line = nullptr;
        size_t size = 0;
        ssize_t n;
        while ((n = getline(&line, &size, f)) > 0) {
            std::string l(line, n);
            while (!l.empty() && (l.back() == '\n' || l.back() == '\r')) {
                l.pop_back();
            }
            auto tab = l.find('\t');
            if (l.empty() || l[0] == '#' || tab == std::string::npos) {
                continue;
            }
            auto name = l.substr(0, tab);
            if (data.empty() || data.back().tab != name) {
                data.push_back({name, {}});
            }
            data.back().items.push_back(l.substr(tab + 1));
        }
        std::free(line);
        std::fclose(f);
    }
}

void Keyboard::setRecent(std::vector<std::string> emoji,
                         std::vector<std::string> kaomoji) {
    recent_[0] = std::move(emoji);
    recent_[1] = std::move(kaomoji);
}

bool Keyboard::isCell(int key) const {
    const auto *k = find(key);
    return k && k->kind == KeyKind::Cell;
}

void Keyboard::openPicker(int page) {
    page_ = page == 1 ? Page::Emoji : Page::Kaomoji;
    menuOpen_ = false;
    // Recent first, unless there's nothing in it yet.
    category_ = recent_[page - 1].empty() ? 1 : 0;
    pickerPage_ = 0;
    layoutPicker();
}

void Keyboard::turnPickerPage(int direction) {
    if (!inPicker()) {
        return;
    }
    const int which = page_ == Page::Emoji ? 0 : 1;
    const int tabs = pickerData(which).size() + 1;
    const int perPage = columns_ * PickerRows;
    const int pages =
        std::max(1, int((shown_.size() + perPage - 1) / perPage));
    pickerPage_ += direction;
    if (pickerPage_ >= pages) {
        if (category_ + 1 >= tabs) {
            pickerPage_ = pages - 1;
            return;
        }
        category_++;
        pickerPage_ = 0;
    } else if (pickerPage_ < 0) {
        // Back into the previous tab, at its end. Recent is skipped when
        // empty.
        if (category_ == 0 || (category_ == 1 && recent_[which].empty())) {
            pickerPage_ = 0;
            return;
        }
        category_--;
        pickerPage_ = -1;
    }
    layoutPicker();
}

void Keyboard::layoutPicker() {
    pickerKeys_.clear();
    if (!inPicker() || width_ <= 0) {
        return;
    }
    const int which = page_ == Page::Emoji ? 0 : 1;
    const auto &data = pickerData(which);
    category_ = std::clamp(category_, 0, int(data.size()));
    shown_ = category_ == 0 ? recent_[which] : data[category_ - 1].items;

    const double inner = width_ - 2 * Edge;
    const double top = Edge + barH_;
    const double rowH = (height_ - Edge - top) / letters_.size();
    // Emoji in squares; kaomoji are wide.
    columns_ = std::max(
        1, int(inner / (which == 0 ? rowH * 1.1 : rowH * 3.4)));
    cellW_ = inner / columns_;
    const int perPage = columns_ * PickerRows;
    const int pages =
        std::max(1, int((shown_.size() + perPage - 1) / perPage));
    if (pickerPage_ < 0 || pickerPage_ >= pages) {
        pickerPage_ = pickerPage_ < 0 ? pages - 1 : 0;
    }
    for (int i = 0; i < perPage; i++) {
        size_t item = pickerPage_ * perPage + i;
        if (item >= shown_.size()) {
            break;
        }
        Key k{KeyKind::Cell, shown_[item]};
        k.x = Edge + (i % columns_) * cellW_;
        k.y = top + (i / columns_) * rowH;
        k.w = cellW_;
        k.h = rowH;
        k.index = item;
        pickerKeys_.push_back(std::move(k));
    }
    // ABC, the tabs, backspace: along the bottom, where the space bar row
    // was.
    const double unit = inner / 10;
    const double y = top + PickerRows * rowH;
    auto add = [&](KeyKind kind, std::string label, double x, double w,
                   int index) {
        Key k{kind, std::move(label)};
        k.x = x;
        k.y = y;
        k.w = w;
        k.h = rowH;
        k.index = index;
        pickerKeys_.push_back(std::move(k));
    };
    // Same spots as on the key pages.
    add(KeyKind::Letters, "ABC", Edge, unit * 1.5, 0);
    add(KeyKind::Lang, "", Edge + unit * 1.5, unit, 0);
    const double tabsX = Edge + unit * 2.5, tabsW = inner - unit * 4;
    const int tabs = data.size() + 1;
    for (int i = 0; i < tabs; i++) {
        add(KeyKind::Tab, i == 0 ? "🕘" : data[i - 1].tab,
            tabsX + i * tabsW / tabs, tabsW / tabs, i);
    }
    add(KeyKind::Backspace, "⌫", Edge + inner - unit * 1.5, unit * 1.5, 0);
}

std::vector<std::vector<Key>> &Keyboard::rows() {
    return symbols_ ? symbolRows_ : kana_ ? kanaRows_ : zhuyin_ ? zhuyinRows_ : letters_;
}

const std::vector<std::vector<Key>> &Keyboard::rows() const {
    return symbols_ ? symbolRows_ : kana_ ? kanaRows_ : zhuyin_ ? zhuyinRows_ : letters_;
}

void Keyboard::resize(double width, double height) {
    width_ = width;
    height_ = height;
    // A strip for candidates and tools, then four rows of keys.
    barH_ = std::round((height - 2 * Edge) * 0.17);
    layoutKeys();
    layoutBar();
    layoutMenu();
    layoutPicker();
}

void Keyboard::layoutKeys() {
    if (width_ <= 0) {
        return;
    }
    const double inner = width_ - 2 * Edge;
    const double top = Edge + barH_;
    // With the pad: ten letter units, a gap, three pad units. Without it the
    // letters take the whole width, for two thumbs.
    const double padUnit = inner * 0.27 / 3;
    const double padX = Edge + inner - 3 * padUnit;
    for (auto *layer : {&letters_, &symbolRows_, &zhuyinRows_, &kanaRows_}) {
        // 注音 has a row more than the others; its keys are that much lower.
        const double rowH = (height_ - Edge - top) / layer->size();
        const bool withPad =
            layer == &symbolRows_ || layer == &kanaRows_ || pad_;
        const double unit = withPad ? inner * 0.70 / 10 : inner / 10;
        if (layer == &letters_) {
            letterUnit_ = unit;
        }
        for (size_t r = 0; r < layer->size(); r++) {
            auto &row = (*layer)[r];
            const bool bottom = r + 1 == layer->size();
            double units = 0, pinned = 0;
            for (const auto &k : row) {
                if (k.pad) {
                    continue;
                }
                if (bottom && pinnedKey(k)) {
                    pinned += k.width;
                } else {
                    units += k.width;
                }
            }
            // ABC/#+= and 中 sit in the same spot on every page, pad or not,
            // so the finger that just switched pages finds them again. The
            // rest of the bottom row takes what's left.
            const double rest =
                bottom ? (10 * unit - pinned * inner / 10) / units : unit;
            // Short letter rows sit centred, like the home row on a real
            // keyboard.
            double x = bottom ? Edge : Edge + (10 - units) * unit / 2;
            double px = padX;
            for (auto &k : row) {
                auto &at = k.pad ? px : x;
                k.x = at;
                k.y = top + r * rowH;
                k.w = k.width * (k.pad              ? padUnit
                                 : !bottom          ? unit
                                 : pinnedKey(k)     ? inner / 10
                                                    : rest);
                k.h = rowH;
                at += k.w;
            }
        }
    }
}

void Keyboard::layoutMenu() {
    menuKeys_.clear();
    if (width_ <= 0 || menu_.empty()) {
        return;
    }
    // A grid over the keys, four across, as tall as the keys' rows.
    const int columns = 4;
    const double top = Edge + barH_;
    const double rowH = (height_ - Edge - top) / letters_.size();
    const double w = (width_ - 2 * Edge) / columns;
    for (size_t i = 0; i < menu_.size(); i++) {
        Key k{KeyKind::MenuItem, menu_[i].label};
        k.x = Edge + (i % columns) * w;
        k.y = top + (i / columns) * rowH;
        k.w = w;
        k.h = rowH;
        k.index = i;
        menuKeys_.push_back(std::move(k));
    }
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
    const double y = Edge, h = barH_;
    const double tool = h * 1.3;
    double right = width_ - Edge;
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
        // As many candidates as fit, left to right; the arrows only appear
        // when some don't, and step through the rest a stripful at a time.
        const double padding = h * 0.45;
        // The preedit sits on the left, small, as rime spells it out.
        double start = Edge;
        if (!candidates_.preedit.empty()) {
            start += textWidth(candidates_.preedit, h * 0.32) + padding * 2;
        }
        auto fill = [&](double limit) {
            double x = start;
            size_t i = offset_;
            for (; i < candidates_.words.size(); i++) {
                const double w =
                    std::max(textWidth(candidates_.words[i], h * 0.48) +
                                 padding * 2,
                             h * 1.4);
                if (x + w > limit) {
                    break;
                }
                add(KeyKind::Candidate, candidates_.words[i], x, w, i);
                x += w;
            }
            return i;
        };
        nextOffset_ = fill(right);
        hasNext_ = nextOffset_ < candidates_.words.size();
        if (hasNext_ || offset_ > 0) {
            bar_.clear();
            right -= tool;
            add(KeyKind::NextPage, "", right, tool);
            right -= tool;
            add(KeyKind::PrevPage, "", right, tool);
            nextOffset_ = fill(right);
            hasNext_ = nextOffset_ < candidates_.words.size();
        }
        return;
    }

    // Idle: tools. Hiding keeps the corner Gboard and Windows give it.
    double left = Edge;
    add(KeyKind::EmojiPage, "😊", left, tool);
    left += tool;
    add(KeyKind::KaomojiPage, "", left, tool);
    right -= tool;
    add(KeyKind::Hide, "", right, tool);
    right -= tool;
    add(KeyKind::More, "", right, tool);
}

void Keyboard::setCandidates(Candidates candidates) {
    // New words from the input method start the strip over.
    if (candidates.words != candidates_.words) {
        offset_ = 0;
        offsets_.clear();
    }
    candidates_ = std::move(candidates);
    if (std::any_of(held_.begin(), held_.end(),
                    [](int k) { return k >= BarBase && k < MenuBase; })) {
        held_.erase(std::remove_if(held_.begin(), held_.end(),
                                   [](int k) {
                                       return k >= BarBase && k < MenuBase;
                                   }),
                    held_.end());
    }
    layoutBar();
}

void Keyboard::setLanguage(bool chinese) { chinese_ = chinese; }

void Keyboard::setInputMethods(std::vector<std::string> labels,
                               int current) {
    imLabels_ = std::move(labels);
    imCurrent_ = current;
}

bool Keyboard::isLang(int key) const {
    const auto *k = find(key);
    return k && k->kind == KeyKind::Lang;
}

void Keyboard::setPad(bool pad) {
    if (pad == pad_) {
        return;
    }
    pad_ = pad;
    layoutKeys();
}

void Keyboard::setMenu(std::vector<MenuEntry> menu) {
    menu_ = std::move(menu);
    layoutMenu();
}

void Keyboard::setFont(std::string font) {
    font_ = std::move(font);
    layoutBar();
}

const Key *Keyboard::find(int key) const {
    if (key < 0) {
        return nullptr;
    }
    if (key >= PickerBase) {
        size_t i = key - PickerBase;
        return i < pickerKeys_.size() ? &pickerKeys_[i] : nullptr;
    }
    if (key >= MenuBase) {
        size_t i = key - MenuBase;
        return i < menuKeys_.size() ? &menuKeys_[i] : nullptr;
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

std::optional<Keyboard::Landing> Keyboard::landing(int key, double x,
                                                   double y) const {
    const auto *k = find(key);
    if (!k || k->kind != KeyKind::Char || k->pad || symbols_ || inPicker()) {
        return std::nullopt;
    }
    return Landing{zhuyin_ ? "zhuyin" : "letters", k->label,
                   (x - k->x - k->w / 2) / k->w,
                   (y - k->y - k->h / 2) / k->h};
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
    if (inPicker()) {
        for (size_t i = 0; i < pickerKeys_.size(); i++) {
            const auto &k = pickerKeys_[i];
            if (x >= k.x && x < k.x + k.w && y >= k.y && y < k.y + k.h) {
                return PickerBase + i;
            }
        }
        return -1;
    }
    if (menuOpen_) {
        for (size_t i = 0; i < menuKeys_.size(); i++) {
            const auto &k = menuKeys_[i];
            if (x >= k.x && x < k.x + k.w && y >= k.y && y < k.y + k.h) {
                return MenuBase + i;
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
        if (!visible(k)) {
            continue;
        }
        const double d = std::max({k.x - x, x - (k.x + k.w), 0.0});
        if (best < 0 || d < bestDistance) {
            best = c;
            bestDistance = d;
        }
    }
    return r * RowStride + best;
}

std::string Keyboard::label(const Key &key) const {
    if (!key.face.empty()) {
        return key.face;
    }
    if (key.kind == KeyKind::Lang) {
        if (imCurrent_ >= 0 && size_t(imCurrent_) < imLabels_.size()) {
            return imLabels_[imCurrent_];
        }
        return chinese_ ? "拼" : "EN";
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
    if (key.kind == KeyKind::Char && (shift_ != Shift::Off || shiftHeld_) &&
        !symbols_ && !key.pad) {
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

bool Keyboard::isShift(int key) const {
    const auto *k = find(key);
    return k && k->kind == KeyKind::Shift;
}

bool Keyboard::isChar(int key) const {
    const auto *k = find(key);
    return k && k->kind == KeyKind::Char;
}

void Keyboard::hold(int key) {
    if (key >= 0) {
        held_.push_back(key);
    }
}

void Keyboard::unhold(int key) {
    auto it = std::find(held_.begin(), held_.end(), key);
    if (it != held_.end()) {
        held_.erase(it);
    }
}

bool Keyboard::isHeld(int key) const {
    return std::find(held_.begin(), held_.end(), key) != held_.end();
}

std::vector<std::string> Keyboard::alternates(int key, int *anchor) const {
    if (anchor) {
        *anchor = 0;
    }
    const auto *k = find(key);
    if (k && k->kind == KeyKind::Lang && imLabels_.size() > 1) {
        if (anchor) {
            *anchor = std::max(imCurrent_, 0);
        }
        return imLabels_;
    }
    if (k && k->kind == KeyKind::Enter && !k->pad) {
        if (anchor) {
            *anchor = -1;
        }
        return {"newline"};
    }
    if (!k || k->kind != KeyKind::Char || k->pad || symbols_) {
        return {};
    }
    if (!k->face.empty()) {
        // The 注音 symbol stays under the finger, what the key is on a plain
        // keyboard goes either side of it. The outer columns keep the row on
        // screen by putting the symbol at their end, since a row pulled in
        // from the edge would leave the finger over another item.
        static const std::map<std::string, std::vector<std::string>> stops = {
            {";", {"：", "；"}},
            {",", {"……", "，"}},
            {".", {"！", "。"}},
            {"/", {"？", "/"}},
        };
        std::vector<std::string> sides{k->label};
        if (auto it = stops.find(k->label); it != stops.end()) {
            sides = it->second;
        } else if (std::isalpha(static_cast<unsigned char>(k->label[0]))) {
            std::string upper = k->label;
            upper[0] = std::toupper(upper[0]);
            sides = {upper, k->label};
        }
        const int column = key % RowStride;
        std::vector<std::string> items;
        int at = 0;
        if (column == 0) {
            items = {k->face};
            items.insert(items.end(), sides.begin(), sides.end());
        } else if (column == 9) {
            items = sides;
            items.push_back(k->face);
            at = items.size() - 1;
        } else if (sides.size() == 2) {
            items = {sides[0], k->face, sides[1]};
            at = 1;
        } else {
            items = {k->face, sides[0]};
        }
        if (anchor) {
            *anchor = at;
        }
        return items;
    }
    // Gboard's: digits along the top row, its symbols under the rest, so
    // the thumbs already know where they are. ASCII goes through the input
    // method like a typed key, so rime still makes ! into ！.
    static const std::map<std::string, std::vector<std::string>> latin = {
        {"q", {"1"}}, {"w", {"2"}}, {"e", {"3"}}, {"r", {"4"}},
        {"t", {"5"}}, {"y", {"6"}}, {"u", {"7"}}, {"i", {"8"}},
        {"o", {"9"}}, {"p", {"0"}}, {"a", {"@"}}, {"s", {"#"}},
        {"d", {"$"}}, {"f", {"_"}}, {"g", {"&"}}, {"h", {"-"}},
        {"j", {"+"}}, {"k", {"("}}, {"l", {")"}}, {"z", {"*"}},
        {"x", {"\""}}, {"c", {"'"}}, {"v", {":"}}, {"b", {";"}},
        {"n", {"!"}}, {"m", {"?"}},
    };
    static const std::map<std::string, std::vector<std::string>> chinese = {
        {".", {"……", "…", "·", "～"}},
        {",", {"、", "；", "：", "\""}},
        // 注音's comma key: the stops its , and . can't give.
        {"，", {"。", "、", "？", "！", "：", "；", "……"}},
    };
    static const std::map<std::string, std::vector<std::string>> english = {
        {".", {"…", "~", "·"}},
        {",", {";", ":", "'"}},
    };
    auto it = latin.find(k->label);
    if (it != latin.end()) {
        // Letters: the symbol under the finger, the letter itself either
        // side of it, upper case left, lower right. Those two go straight
        // into the text, past rime.
        std::string upper = k->label;
        upper[0] = std::toupper(upper[0]);
        if (anchor) {
            *anchor = 1;
        }
        return {upper, it->second[0], k->label};
    }
    const auto &table = chinese_ ? chinese : english;
    it = table.find(k->label);
    return it != table.end() ? it->second : std::vector<std::string>{};
}

bool Keyboard::isFlick(int key) const {
    const auto *k = find(key);
    return k && k->pad && flickItems(k->label);
}

void Keyboard::flickStart(int key, double x, double y) {
    flick_ = {key, x, y, 0};
}

void Keyboard::flickMove(double x, double y) {
    const auto *k = find(flick_.key);
    const auto *items = k ? flickItems(k->label) : nullptr;
    if (!items) {
        return;
    }
    const double dx = x - flick_.x, dy = y - flick_.y;
    int direction = 0;
    if (std::hypot(dx, dy) >= 0.35 * std::min(k->w, k->h)) {
        direction = std::abs(dx) > std::abs(dy) ? (dx < 0 ? 1 : 3)
                                                : (dy < 0 ? 2 : 4);
    }
    flick_.direction = *(*items)[direction] ? direction : 0;
}

bool Keyboard::longPresses(int key) const {
    const auto *k = find(key);
    return k && !alternates(key).empty();
}

void Keyboard::openPopup(int key) {
    const auto *k = find(key);
    int anchor = 0;
    auto items = alternates(key, &anchor);
    if (!k || items.empty()) {
        return;
    }
    popup_.key = key;
    popup_.items = std::move(items);
    popup_.selected = popup_.anchor = anchor;
    popup_.itemW = k->w;
    popup_.h = k->h;
    // Above the key with the anchor over it, pulled back in at the edges.
    // The top row's sits over the strip.
    const double total = popup_.itemW * popup_.items.size();
    popup_.x = std::clamp(k->x - std::max(anchor, 0) * popup_.itemW, Edge,
                          width_ - Edge - total);
    popup_.y = std::max(Edge, k->y - k->h);
}

void Keyboard::popupMove(double x, double y) {
    if (popup_.key < 0) {
        return;
    }
    // Still on the key: nothing, for a row that has to be slid into.
    if (popup_.anchor < 0 && y > popup_.y + popup_.h) {
        popup_.selected = -1;
        return;
    }
    const int n = popup_.items.size();
    popup_.selected =
        std::clamp(int(std::floor((x - popup_.x) / popup_.itemW)), 0, n - 1);
}

std::string Keyboard::closePopup() {
    std::string text;
    popupPicked_ = popup_.key >= 0 ? popup_.selected : -1;
    if (popup_.key >= 0 && popup_.selected >= 0) {
        text = popup_.items[popup_.selected];
        if (text == "newline") {
            text = "\n";
        }
    }
    popup_ = {};
    return text;
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
    const auto *k = find(key);
    Action a;
    std::string lastKana;
    lastKana.swap(lastKana_);
    if (!k) {
        dragging_ = dragMoved_ = false;
        return a;
    }
    bool dragged = false;
    if (k->kind == KeyKind::Space) {
        dragged = dragging_ && dragMoved_;
        dragging_ = dragMoved_ = false;
    }
    switch (k->kind) {
    case KeyKind::Char: {
        // Send the key itself, not what's printed on it: rime decides
        // whether ',' becomes '，'.
        if (flick_.key == key) {
            if (k->label == "゛小") {
                static const int which[5] = {0, 1, 0, 2, 3};
                lastKana_ = nextKanaForm(lastKana, which[flick_.direction]);
                if (!lastKana_.empty()) {
                    a.romaji = romajiOf(lastKana_);
                    a.eraseFirst = true;
                } else {
                    lastKana_ = lastKana;
                }
            } else if (const auto *items = flickItems(k->label)) {
                lastKana_ = (*items)[flick_.direction];
                a.romaji = romajiOf(lastKana_);
            }
            flick_ = {};
            break;
        }
        auto s = k->label;
        if (static_cast<unsigned char>(s[0]) >= 0x80) {
            // Not a key at all (注音's ，): straight in.
            a.text = s;
            break;
        }
        const bool upper = (shift_ != Shift::Off || shiftHeld_) && !zhuyin_;
        if (upper && !symbols_ && !k->pad) {
            std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        }
        if (shiftHeld_) {
            // Held like a real shift: it leaves no state behind.
            shiftUsed_ = true;
        } else if (shift_ == Shift::Once) {
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
    case KeyKind::CursorRight:
        a.sym = 0xff53;
        break;
    case KeyKind::Backspace:
        // Sent on press, and repeated while held.
        break;
    case KeyKind::Shift: {
        const bool chord = shiftUsed_;
        shiftHeld_ = shiftUsed_ = false;
        if (chord) {
            break;
        }
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
    case KeyKind::More:
        menuOpen_ = !menuOpen_;
        a.menuOpened = menuOpen_;
        break;
    case KeyKind::MenuItem:
        // Stays open, so the switch is seen to flip.
        a.menuItem = k->index;
        break;
    case KeyKind::Candidate:
        a.candidate = k->index;
        break;
    case KeyKind::EmojiPage:
    case KeyKind::KaomojiPage: {
        const auto page =
            k->kind == KeyKind::EmojiPage ? Page::Emoji : Page::Kaomoji;
        if (page_ == page) {
            page_ = Page::Keys;
        } else {
            openPicker(page == Page::Emoji ? 1 : 2);
        }
        layoutBar();
        break;
    }
    case KeyKind::Letters:
        page_ = Page::Keys;
        layoutBar();
        break;
    case KeyKind::Tab:
        category_ = k->index;
        pickerPage_ = 0;
        layoutPicker();
        break;
    case KeyKind::Cell: {
        a.text = k->label;
        // The open tab keeps its order until it's opened again, so nothing
        // jumps under the finger.
        auto &recent = recent_[page_ == Page::Emoji ? 0 : 1];
        recent.erase(std::remove(recent.begin(), recent.end(), a.text),
                     recent.end());
        recent.insert(recent.begin(), a.text);
        if (recent.size() > RecentMax) {
            recent.resize(RecentMax);
        }
        a.recentChanged = true;
        break;
    }
    case KeyKind::PrevPage:
        if (!offsets_.empty()) {
            offset_ = offsets_.back();
            offsets_.pop_back();
            layoutBar();
        }
        break;
    case KeyKind::NextPage:
        if (hasNext_) {
            offsets_.push_back(offset_);
            offset_ = nextOffset_;
            layoutBar();
        }
        break;
    }
    return a;
}

void Keyboard::reset() {
    symbols_ = false;
    menuOpen_ = false;
    page_ = Page::Keys;
    shift_ = Shift::Off;
    shiftHeld_ = shiftUsed_ = false;
    held_.clear();
    popup_ = {};
    flick_ = {};
    dragging_ = dragMoved_ = false;
}

void Keyboard::paintBar(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                        PangoFontDescription *font) const {
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
        showText(candidates_.preedit, barH_ * 0.32, Edge + barH_ * 0.45, Edge,
                 0, barH_, faded(theme.text, 0.55), false);
    }

    for (size_t i = 0; i < bar_.size(); i++) {
        const auto &k = bar_[i];
        // The open menu's button stays lit, like a held shift.
        if (isHeld(BarBase + i) ||
            (k.kind == KeyKind::More && menuOpen_) ||
            (k.kind == KeyKind::EmojiPage && page_ == Page::Emoji) ||
            (k.kind == KeyKind::KaomojiPage && page_ == Page::Kaomoji)) {
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
            // The highlighted one is what space would pick.
            showText(k.label, barH_ * 0.48, k.x, k.y, k.w, k.h,
                     k.index == candidates_.cursor ? theme.accent
                                                   : theme.text,
                     true);
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
            const bool enabled =
                k.kind == KeyKind::PrevPage ? offset_ > 0 : hasNext_;
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
        case KeyKind::EmojiPage:
            drawIcon(cr, "😊", cx, cy, k.h * 0.26, theme.text);
            break;
        case KeyKind::KaomojiPage:
            drawIcon(cr, "kaomoji", cx, cy, k.h * 0.26, theme.text);
            break;
        case KeyKind::More:
            // Three dots.
            for (int d = -1; d <= 1; d++) {
                cairo_arc(cr, cx + d * r * 1.4, cy, r * 0.28, 0, 2 * M_PI);
                setColor(cr, theme.text);
                cairo_fill(cr);
            }
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

    if (inPicker()) {
        paintPicker(cr, theme, layout, font);
        pango_font_description_free(font);
        g_object_unref(layout);
        return;
    }

    if (menuOpen_) {
        for (size_t i = 0; i < menuKeys_.size(); i++) {
            const auto &k = menuKeys_[i];
            const bool down = isHeld(MenuBase + i);
            // Switches that are on look like a held shift.
            const bool on = menu_[i].checked;
            Color fill = theme.key;
            if (down || on) {
                fill = mix(fill, theme.accent, down ? 0.3 : 0.2);
            }
            roundedRect(cr, k.x + gap, k.y + gap, k.w - 2 * gap,
                        k.h - 2 * gap, radius);
            setColor(cr, fill);
            if (down || on) {
                cairo_fill_preserve(cr);
                setColor(cr, theme.accent);
                cairo_set_line_width(cr, 1.5);
                cairo_stroke(cr);
            } else {
                cairo_fill(cr);
            }
            drawText(k.label, k.h * 0.32, k.x, k.y, k.w, k.h, theme.text);
        }
        pango_font_description_free(font);
        g_object_unref(layout);
        return;
    }

    for (size_t r = 0; r < rs.size(); r++) {
        for (size_t c = 0; c < rs[r].size(); c++) {
            const auto &k = rs[r][c];
            if (!visible(k)) {
                continue;
            }
            const bool down = isHeld(r * RowStride + c);
            const bool special = k.kind != KeyKind::Char &&
                                 k.kind != KeyKind::Space;
            Color fill = special ? theme.keyAlt : theme.key;
            // Pressed keys and an active shift look like the selected
            // candidate in fcitx's plasma theme: accent-tinted, outlined.
            const bool lit =
                down || (k.kind == KeyKind::Shift &&
                         (shift_ != Shift::Off || shiftHeld_));
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
            if (k.kind == KeyKind::CursorRight || text == "␣") {
                drawIcon(cr, text, k.x + k.w / 2, k.y + k.h / 2, k.h * 0.2,
                         theme.text);
                continue;
            }
            const bool small = (text.size() > 3 && k.kind == KeyKind::Layer) ||
                               k.kind == KeyKind::Lang || text == "゛小" ||
                               text == "、。";
            drawText(text, k.h * (small ? 0.30 : 0.46), k.x, k.y, k.w, k.h,
                     theme.text);

            // What holding gives, faint in the corner, as Gboard prints the
            // digits on its top row. The pinyin hints take the corner when
            // they're on.
            const bool pinyinHint = hints_ && chinese_ && !symbols_ &&
                                    !zhuyin_ && !k.pad &&
                                    k.kind == KeyKind::Char &&
                                    flypyFinals().count(k.label[0]);
            if (!k.face.empty() && !symbols_) {
                // 注音 keys: the plain key they sit on, as Gboard prints it.
                pango_font_description_set_absolute_size(
                    font, k.h * 0.2 * PANGO_SCALE);
                pango_layout_set_font_description(layout, font);
                // Letters and digits print themselves; the keys whose plain
                // character is punctuation print the stop they give.
                std::string corner = k.label;
                if (!std::isalnum(static_cast<unsigned char>(corner[0]))) {
                    for (const auto &item : alternates(r * RowStride + c)) {
                        if (item != k.face) {
                            corner = item;
                            break;
                        }
                    }
                }
                pango_layout_set_text(layout, corner.c_str(), -1);
                int tw, th;
                pango_layout_get_pixel_size(layout, &tw, &th);
                setColor(cr, faded(theme.text, 0.4));
                cairo_move_to(cr, k.x + k.w - gap - tw - 4, k.y + gap + 2);
                pango_cairo_show_layout(cr, layout);
            } else if (!pinyinHint) {
                int anchor = 0;
                const auto alt = alternates(r * RowStride + c, &anchor);
                // Only letters and punctuation print theirs.
                if (!alt.empty() && anchor >= 0 && k.kind == KeyKind::Char) {
                    pango_font_description_set_absolute_size(
                        font, k.h * 0.2 * PANGO_SCALE);
                    pango_layout_set_font_description(layout, font);
                    pango_layout_set_text(layout, alt[anchor].c_str(), -1);
                    int tw, th;
                    pango_layout_get_pixel_size(layout, &tw, &th);
                    setColor(cr, faded(theme.text, 0.4));
                    cairo_move_to(cr, k.x + k.w - gap - tw - 4,
                                  k.y + gap + 2);
                    pango_cairo_show_layout(cr, layout);
                }
            }
            if (pinyinHint) {
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
    paintPopup(cr, theme, layout, font);
    paintFlick(cr, theme, layout, font);
    pango_font_description_free(font);
    g_object_unref(layout);
}

void Keyboard::paintPicker(cairo_t *cr, const Theme &theme,
                           PangoLayout *layout,
                           PangoFontDescription *font) const {
    const double gap = 3, radius = 5;
    auto text = [&](const std::string &s, double size, const Key &k,
                    const Color &color) {
        pango_font_description_set_absolute_size(font, size * PANGO_SCALE);
        pango_layout_set_font_description(layout, font);
        pango_layout_set_text(layout, s.c_str(), -1);
        int tw, th;
        pango_layout_get_pixel_size(layout, &tw, &th);
        // Kaomoji too wide for their cell shrink rather than spill.
        if (tw > k.w - 2 * gap - 4) {
            const double fit = size * (k.w - 2 * gap - 4) / tw;
            pango_font_description_set_absolute_size(font,
                                                     fit * PANGO_SCALE);
            pango_layout_set_font_description(layout, font);
            pango_layout_get_pixel_size(layout, &tw, &th);
        }
        setColor(cr, color);
        cairo_move_to(cr, k.x + (k.w - tw) / 2, k.y + (k.h - th) / 2);
        pango_cairo_show_layout(cr, layout);
    };
    const bool emoji = page_ == Page::Emoji;
    if (shown_.empty() && !pickerKeys_.empty()) {
        Key k{KeyKind::Cell, ""};
        k.x = Edge;
        k.y = Edge + barH_;
        k.w = width_ - 2 * Edge;
        k.h = pickerKeys_.back().y - k.y;
        text("用过的会出现在这里", k.h * 0.12, k, faded(theme.text, 0.4));
    }
    for (size_t i = 0; i < pickerKeys_.size(); i++) {
        const auto &k = pickerKeys_[i];
        const bool down = isHeld(PickerBase + i);
        switch (k.kind) {
        case KeyKind::Cell:
            // Bare, like Gboard's grid; a pressed one gets the key look.
            if (down) {
                roundedRect(cr, k.x + gap, k.y + gap, k.w - 2 * gap,
                            k.h - 2 * gap, radius);
                setColor(cr, mix(theme.key, theme.accent, 0.3));
                cairo_fill_preserve(cr);
                setColor(cr, theme.accent);
                cairo_set_line_width(cr, 1.5);
                cairo_stroke(cr);
            }
            text(k.label, k.h * (emoji ? 0.52 : 0.36), k, theme.text);
            break;
        case KeyKind::Tab: {
            const bool on = k.index == category_;
            if (on || down) {
                roundedRect(cr, k.x + gap, k.y + gap, k.w - 2 * gap,
                            k.h - 2 * gap, radius);
                setColor(cr,
                         mix(theme.keyAlt, theme.accent, down ? 0.3 : 0.2));
                cairo_fill_preserve(cr);
                setColor(cr, theme.accent);
                cairo_set_line_width(cr, 1.5);
                cairo_stroke(cr);
            }
            // Kaomoji tabs are words; emoji tabs and recent are line icons.
            if (!drawIcon(cr, k.label, k.x + k.w / 2, k.y + k.h / 2,
                          k.h * 0.2, faded(theme.text, on ? 1 : 0.7))) {
                text(k.label, k.h * 0.3, k, faded(theme.text, on ? 1 : 0.7));
            }
            break;
        }
        default:
            roundedRect(cr, k.x + gap, k.y + gap, k.w - 2 * gap,
                        k.h - 2 * gap, radius);
            setColor(cr, down ? mix(theme.keyAlt, theme.accent, 0.3)
                              : theme.keyAlt);
            cairo_fill(cr);
            text(label(k), k.h * (k.kind == KeyKind::Lang ? 0.30 : 0.46),
                 k, theme.text);
            break;
        }
    }
    // Where in the tab: a thin line over the bottom row, one screenful's
    // share long.
    const int perPage = columns_ * PickerRows;
    const int pages =
        std::max(1, int((shown_.size() + perPage - 1) / perPage));
    if (pages > 1 && !pickerKeys_.empty()) {
        const double y = pickerKeys_.back().y - 2;
        const double w = (width_ - 2 * Edge) / pages;
        setColor(cr, faded(theme.accent, 0.8));
        cairo_rectangle(cr, Edge + pickerPage_ * w, y, w, 2);
        cairo_fill(cr);
    }
}

void Keyboard::paintFlick(cairo_t *cr, const Theme &theme,
                          PangoLayout *layout,
                          PangoFontDescription *font) const {
    const auto *k = find(flick_.key);
    const auto *items = k ? flickItems(k->label) : nullptr;
    if (!items) {
        return;
    }
    const double w = k->w, h = k->h;
    // Pulled in from the screen's edges; only the direction counts, so the
    // cross needn't be centred on the finger.
    const double cx = std::clamp(k->x + w / 2, Edge + 1.5 * w,
                                 width_ - Edge - 1.5 * w);
    const double cy = std::clamp(k->y + h / 2, Edge + 1.5 * h,
                                 height_ - Edge - 1.5 * h);
    auto text = [&](const char *s, double size, double mx, double my) {
        pango_font_description_set_absolute_size(font, size * PANGO_SCALE);
        pango_layout_set_font_description(layout, font);
        pango_layout_set_text(layout, s, -1);
        int tw, th;
        pango_layout_get_pixel_size(layout, &tw, &th);
        setColor(cr, theme.text);
        cairo_move_to(cr, mx - tw / 2.0, my - th / 2.0);
        pango_cairo_show_layout(cr, layout);
    };
    const double offset[5][2] = {{0, 0}, {-1, 0}, {0, -1}, {1, 0}, {0, 1}};
    for (int i = 0; i < 5; i++) {
        if (!*(*items)[i]) {
            continue;
        }
        const double mx = cx + offset[i][0] * w, my = cy + offset[i][1] * h;
        const bool selected = i == flick_.direction;
        roundedRect(cr, mx - w / 2 + 1, my - h / 2 + 1, w - 2, h - 2, 7);
        setColor(cr, selected ? mix(theme.key, theme.accent, 0.3) : theme.key);
        cairo_fill_preserve(cr);
        setColor(cr, selected ? theme.accent : faded(theme.text, 0.2));
        cairo_set_line_width(cr, selected ? 1.5 : 1);
        cairo_stroke(cr);
        text((*items)[i], h * 0.42, mx, my);
    }
    // The thumb covers the cross's middle and lower half, so what's picked
    // is shown again out to its left.
    const double size = h * 1.3;
    const double px = cx - 1.5 * w - 8 - size;
    const double py = std::max(Edge, cy - size / 2);
    roundedRect(cr, px, py, size, size, 9);
    setColor(cr, mix(theme.key, theme.accent, 0.3));
    cairo_fill_preserve(cr);
    setColor(cr, theme.accent);
    cairo_set_line_width(cr, 1.5);
    cairo_stroke(cr);
    text((*items)[flick_.direction], size * 0.6, px + size / 2, py + size / 2);
}

void Keyboard::paintPopup(cairo_t *cr, const Theme &theme,
                          PangoLayout *layout,
                          PangoFontDescription *font) const {
    if (popup_.key < 0) {
        return;
    }
    const double w = popup_.itemW * popup_.items.size();
    // A raised card: the key colour, a hairline, a soft shadow below.
    roundedRect(cr, popup_.x + 1, popup_.y + 3, w, popup_.h, 7);
    setColor(cr, faded(Color{0, 0, 0}, 0.25));
    cairo_fill(cr);
    roundedRect(cr, popup_.x, popup_.y, w, popup_.h, 7);
    setColor(cr, theme.key);
    cairo_fill_preserve(cr);
    setColor(cr, faded(theme.text, 0.2));
    cairo_set_line_width(cr, 1);
    cairo_stroke(cr);
    for (size_t i = 0; i < popup_.items.size(); i++) {
        const double x = popup_.x + i * popup_.itemW;
        const bool selected = int(i) == popup_.selected;
        if (selected) {
            roundedRect(cr, x + 3, popup_.y + 3, popup_.itemW - 6,
                        popup_.h - 6, 5);
            setColor(cr, mix(theme.key, theme.accent, 0.3));
            cairo_fill_preserve(cr);
            setColor(cr, theme.accent);
            cairo_set_line_width(cr, 1.5);
            cairo_stroke(cr);
        }
        if (drawIcon(cr, popup_.items[i], x + popup_.itemW / 2,
                     popup_.y + popup_.h / 2, popup_.h * 0.24, theme.text)) {
            continue;
        }
        pango_font_description_set_absolute_size(
            font, popup_.h * 0.42 * PANGO_SCALE);
        pango_layout_set_font_description(layout, font);
        pango_layout_set_text(layout, popup_.items[i].c_str(), -1);
        int tw, th;
        pango_layout_get_pixel_size(layout, &tw, &th);
        setColor(cr, theme.text);
        cairo_move_to(cr, x + (popup_.itemW - tw) / 2,
                      popup_.y + (popup_.h - th) / 2);
        pango_cairo_show_layout(cr, layout);
    }
}

} // namespace hotaru
