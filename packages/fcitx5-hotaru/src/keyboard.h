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
    Script,    // rime's 漢字 / 汉字 switch
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
    int index = 0;          // candidates: position on the current page
};

// What the input method is showing, as far as the keyboard cares.
struct Candidates {
    std::string preedit;
    std::vector<std::string> words;
    bool hasPrev = false, hasNext = false;
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
        bool toggleScript = false;
        int candidate = -1; // index on the current page to pick
        int page = 0;       // -1 / +1 to turn the candidate page
    };
    // Finger lifted on a key. Updates shift and layer state.
    Action release(int key);

    void reset();

    void setCandidates(Candidates candidates);
    // chinese: rime is the input method. scriptLabel: rime's simplified /
    // traditional switch as rime words it, empty to leave it out.
    void setLanguage(bool chinese, std::string scriptLabel);
    // Double pinyin: print each key's final in its corner.
    void setHints(bool hints) { hints_ = hints; }
    void setFont(std::string font);

private:
    std::vector<std::vector<Key>> &rows();
    const std::vector<std::vector<Key>> &rows() const;
    const Key *find(int key) const;
    std::string label(const Key &key) const;
    bool composing() const;
    double textWidth(const std::string &text, double size) const;
    void layoutBar();
    void paintBar(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                  PangoFontDescription *font) const;

    enum class Shift { Off, Once, Locked };
    std::vector<std::vector<Key>> letters_, symbolRows_;
    std::vector<Key> bar_;
    Candidates candidates_;
    std::string scriptLabel_;
    std::string font_ = "Noto Sans";
    bool chinese_ = false;
    bool symbols_ = false;
    bool hints_ = false;
    Shift shift_ = Shift::Off;
    int pressed_ = -1;
    uint64_t lastShiftTap_ = 0;
    bool dragging_ = false, dragMoved_ = false;
    double dragOrigin_ = 0;
    double width_ = 0, height_ = 0, barH_ = 0, letterUnit_ = 0;
};

} // namespace hotaru
