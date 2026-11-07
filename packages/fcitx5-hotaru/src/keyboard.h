#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <cairo.h>
#include <pango/pangocairo.h>
#include "theme.h"

namespace hotaru {

enum class KeyKind {
    Char,
    Shift,
    Backspace,
    Enter,
    Layer,
    Space,
    Lang,      // 中 / EN
    Hide,
    More,      // opens the menu of input method switches
    MenuItem,
    Candidate,
    PrevPage,
    NextPage,
};

struct Key {
    KeyKind kind;
    std::string label;      // letters: the lower-case form
    double width = 1;       // in units of its block's key width
    bool pad = false;       // in the number pad on the right
    double x = 0, y = 0, w = 0, h = 0;
    int index = 0;          // candidates, menu items: which one
};

// What the input method is showing, as far as the keyboard cares.
// words holds every candidate the input method will give, not just its
// current page; the strip shows as many as fit.
struct Candidates {
    std::string preedit;
    std::vector<std::string> words;
    int cursor = 0; // the one space would pick
};

// One switch from the input method's status area: 中/西, 半角/全角, 汉/漢…
struct MenuEntry {
    std::string label;
    bool checked = false;
};

// Layout, state and drawing; knows nothing about Wayland or fcitx.
class Keyboard {
public:
    Keyboard();

    void resize(double width, double height);
    void paint(cairo_t *cr, const Theme &theme) const;

    // Index of the key under (x, y), or -1. Gaps between keys belong to the
    // nearest key, so a tap never falls through.
    int keyAt(double x, double y) const;

    // The finger is down on (or has slid onto) a key.
    void setPressed(int key) { pressed_ = key; }
    int pressed() const { return pressed_; }
    bool repeats(int key) const;
    bool isSpace(int key) const;
    // The finger is sliding along space: arrow keys to move the cursor by.
    std::vector<uint32_t> dragSpace(double x);

    struct Action {
        uint32_t sym = 0; // keysym to type, or 0
        bool hide = false;
        bool toggleLanguage = false;
        bool menuOpened = false; // the menu just opened: fill it
        int menuItem = -1;
        int candidate = -1; // index into Candidates::words to pick
    };
    // Finger lifted on a key. Updates shift, layer and menu state.
    Action release(int key);

    void reset();

    void setCandidates(Candidates candidates);
    // rime (or another real input method) rather than a plain layout.
    void setLanguage(bool chinese);
    // Number pad beside the letters: for passwords and digits. Elsewhere it
    // only comes out on the symbols page, and letters get the full width.
    void setPad(bool pad);
    void setMenu(std::vector<MenuEntry> menu);
    // Double pinyin: print each key's final in its corner.
    void setHints(bool hints) { hints_ = hints; }
    void setFont(std::string font);

private:
    std::vector<std::vector<Key>> &rows();
    const std::vector<std::vector<Key>> &rows() const;
    bool padShown() const { return pad_ || symbols_; }
    bool visible(const Key &key) const { return !key.pad || padShown(); }
    const Key *find(int key) const;
    std::string label(const Key &key) const;
    bool composing() const;
    double textWidth(const std::string &text, double size) const;
    void layoutKeys();
    void layoutBar();
    void layoutMenu();
    void paintBar(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                  PangoFontDescription *font) const;

    enum class Shift { Off, Once, Locked };
    std::vector<std::vector<Key>> letters_, symbolRows_;
    std::vector<Key> bar_, menuKeys_;
    std::vector<MenuEntry> menu_;
    Candidates candidates_;
    std::string font_ = "Noto Sans";
    bool chinese_ = false;
    bool pad_ = true;
    bool symbols_ = false;
    bool menuOpen_ = false;
    bool hints_ = false;
    Shift shift_ = Shift::Off;
    int pressed_ = -1;
    uint64_t lastShiftTap_ = 0;
    bool dragging_ = false, dragMoved_ = false;
    double dragOrigin_ = 0;
    // The strip's view into the candidates: where it starts, where the next
    // stripful would, and where the earlier ones did.
    size_t offset_ = 0, nextOffset_ = 0;
    std::vector<size_t> offsets_;
    bool hasNext_ = false;
    double width_ = 0, height_ = 0, barH_ = 0, letterUnit_ = 0;
};

} // namespace hotaru
