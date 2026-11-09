#pragma once

#include <optional>
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
    CursorRight,
    Layer,
    Space,
    Lang,      // 中 / EN
    Hide,
    More,      // opens the menu of input method switches
    MenuItem,
    Candidate,
    PrevPage,
    NextPage,
    EmojiPage,   // the strip's 😊: the emoji page in place of the keys
    KaomojiPage, // the strip's (・ω・)
    Letters,     // back to the keys from a picker page
    Tab,         // a picker page's category
    Cell,        // something to put in, on a picker page
};

struct Key {
    KeyKind kind;
    std::string label;      // letters: the lower-case form
    double width = 1;       // in units of its block's key width
    bool pad = false;       // in the number pad on the right
    std::string face;       // printed instead of label: ㄅ on the 1 key
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
    // Where a press came down on a typing key, in key sizes from its centre.
    // Nothing for number pads, symbols and picker pages.
    struct Landing {
        std::string page, key;
        double dx = 0, dy = 0;
    };
    std::optional<Landing> landing(int key, double x, double y) const;

    // Keys under a finger, drawn lit. Several fingers can be down.
    void hold(int key);
    void unhold(int key);
    bool repeats(int key) const;
    bool isSpace(int key) const;
    bool isShift(int key) const;
    // A plain key that types on release; a second finger landing types it
    // at once, so fast two-thumb typing doesn't wait for the first lift.
    bool isChar(int key) const;
    // A finger is on shift: letters other fingers type are upper case, and
    // shift itself doesn't toggle when it lifts.
    void shiftDown() { shiftHeld_ = true, shiftUsed_ = false; }
    // The finger slid off shift without lifting.
    void shiftLeave() { shiftHeld_ = false; }

    // What holding a key gives: a row above it. The one at anchor sits over
    // the key and is picked unless the finger moves; an anchor of -1 (Enter)
    // picks nothing until the finger slides up into the row, so lifting
    // where it was is still a plain tap.
    std::vector<std::string> alternates(int key, int *anchor = nullptr) const;
    bool longPresses(int key) const;
    // The row of alternates above a held key; the finger slides along it.
    void openPopup(int key);
    void popupMove(double x, double y);
    // What the finger is on, closing the popup: "" for nothing, "\n" for
    // Enter's line break.
    std::string closePopup();
    // Which item closePopup() took, for rows that aren't text (the language
    // key's).
    int popupPicked() const { return popupPicked_; }
    bool isLang(int key) const;
    // Kana keys pick by direction from where the finger came down. The key
    // types what's picked when it's released.
    bool isFlick(int key) const;
    void flickStart(int key, double x, double y);
    void flickMove(double x, double y);
    bool popupOpen() const { return popup_.key >= 0; }
    // The finger is sliding along space: arrow keys to move the cursor by.
    std::vector<uint32_t> dragSpace(double x);

    struct Action {
        uint32_t sym = 0; // keysym to type, or 0
        std::string text; // or text to put in as is
        // Typed key by key for mozc, after a backspace if eraseFirst: ゛ on
        // か takes the か back and spells が.
        std::string romaji;
        bool eraseFirst = false;
        bool hide = false;
        bool toggleLanguage = false;
        bool menuOpened = false; // the menu just opened: fill it
        int menuItem = -1;
        int candidate = -1; // index into Candidates::words to pick
        bool recentChanged = false;
    };
    // Finger lifted on a key. Updates shift, layer and menu state.
    Action release(int key);

    void reset();

    void setCandidates(Candidates candidates);
    // rime (or another real input method) rather than a plain layout.
    void setLanguage(bool chinese);
    // The input methods to pick from by holding the language key, by their
    // short labels, and which is on.
    void setInputMethods(std::vector<std::string> labels, int current);
    // Number pad beside the letters: for passwords and digits. Elsewhere it
    // only comes out on the symbols page, and letters get the full width.
    void setPad(bool pad);
    // rime on its 注音 schema: the 大千 layout, ㄅㄆㄇㄈ on the keys.
    void setZhuyin(bool zhuyin) { zhuyin_ = zhuyin; }
    bool zhuyin() const { return zhuyin_; }
    // Japanese: letters for romaji, 12-key kana where the number pad goes.
    void setKana(bool kana) { kana_ = kana; }
    void setMenu(std::vector<MenuEntry> menu);
    // Double pinyin: print each key's final in its corner.
    void setHints(bool hints) { hints_ = hints; }
    void setFont(std::string font);
    // Emoji and kaomoji lists: "tab\titem" lines in emoji.txt and
    // kaomoji.txt under dir. Read once, shared by every keyboard.
    static void loadData(const std::string &dir);
    // Most recent first; the pickers' first tab.
    void setRecent(std::vector<std::string> emoji,
                   std::vector<std::string> kaomoji);
    const std::vector<std::string> &recentEmoji() const { return recent_[0]; }
    const std::vector<std::string> &recentKaomoji() const {
        return recent_[1];
    }

    bool inPicker() const { return page_ != Page::Keys; }
    bool isCell(int key) const;
    double cellWidth() const { return cellW_; }
    // A swipe across the cells: the next or previous screenful, running on
    // into the neighbouring tab.
    void turnPickerPage(int direction);

private:
    std::vector<std::vector<Key>> &rows();
    const std::vector<std::vector<Key>> &rows() const;
    bool padShown() const { return pad_ || symbols_ || kana_; }
    bool visible(const Key &key) const { return !key.pad || padShown(); }
    const Key *find(int key) const;
    std::string label(const Key &key) const;
    bool composing() const;
    double textWidth(const std::string &text, double size) const;
    void layoutKeys();
    void layoutBar();
    void layoutMenu();
    void layoutPicker();
    void openPicker(int page);
    void paintPicker(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                     PangoFontDescription *font) const;
    void paintBar(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                  PangoFontDescription *font) const;

    enum class Shift { Off, Once, Locked };
    std::vector<std::vector<Key>> letters_, symbolRows_, zhuyinRows_, kanaRows_;
    bool zhuyin_ = false;
    bool kana_ = false;
    std::string lastKana_; // what ゛小 acts on; any other key forgets it
    struct Flick {
        int key = -1;
        double x = 0, y = 0;
        int direction = 0; // into the key's five: centre, left, up, right, down
    } flick_;
    void paintFlick(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                    PangoFontDescription *font) const;
    std::vector<Key> bar_, menuKeys_;
    std::vector<MenuEntry> menu_;
    Candidates candidates_;
    std::string font_ = "Noto Sans";
    // Keys, or a picker page in their place: 1 is emoji, 2 kaomoji.
    enum class Page { Keys, Emoji, Kaomoji };
    Page page_ = Page::Keys;
    int category_ = 0, pickerPage_ = 0;
    std::vector<std::string> shown_; // the open tab's, as it was opened
    std::vector<Key> pickerKeys_;
    int columns_ = 1;
    double cellW_ = 0;
    std::vector<std::string> recent_[2];
    bool chinese_ = false;
    std::vector<std::string> imLabels_;
    int imCurrent_ = -1;
    int popupPicked_ = -1;
    bool pad_ = true;
    bool symbols_ = false;
    bool menuOpen_ = false;
    bool hints_ = false;
    Shift shift_ = Shift::Off;
    bool shiftHeld_ = false, shiftUsed_ = false;
    std::vector<int> held_;
    bool isHeld(int key) const;
    struct Popup {
        int key = -1;
        std::vector<std::string> items;
        int selected = 0, anchor = 0;
        double x = 0, y = 0, itemW = 0, h = 0;
    } popup_;
    void paintPopup(cairo_t *cr, const Theme &theme, PangoLayout *layout,
                    PangoFontDescription *font) const;
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
