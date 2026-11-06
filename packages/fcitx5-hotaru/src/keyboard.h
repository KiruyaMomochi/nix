#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <cairo.h>
#include "theme.h"

namespace hotaru {

enum class KeyKind { Char, Shift, Backspace, Enter, Layer, Space, Hide };

struct Key {
    KeyKind kind;
    std::string label;      // letters: the lower-case form
    double width = 1;       // in units of its block's key width
    bool pad = false;       // in the number pad on the right
    double x = 0, y = 0, w = 0, h = 0;
};

// Layout, state and drawing; knows nothing about Wayland or fcitx.
class Keyboard {
public:
    Keyboard();

    void resize(double width, double height);
    void paint(cairo_t *cr, const Theme &theme) const;

    // Index of the key under (x, y). Gaps belong to the nearest key, so a
    // tap never falls through.
    int keyAt(double x, double y) const;

    // The finger is down on (or has slid onto) a key.
    void setPressed(int key) { pressed_ = key; }
    int pressed() const { return pressed_; }
    bool repeats(int key) const;

    struct Action {
        uint32_t sym = 0; // keysym to type, or 0
        bool hide = false;
    };
    // Finger lifted on a key. Updates shift and layer state.
    Action release(int key);

    void reset();

private:
    std::vector<std::vector<Key>> &rows();
    const std::vector<std::vector<Key>> &rows() const;
    const Key *find(int key) const;
    std::string label(const Key &key) const;

    enum class Shift { Off, Once, Locked };
    std::vector<std::vector<Key>> letters_, symbolRows_;
    bool symbols_ = false;
    Shift shift_ = Shift::Off;
    int pressed_ = -1;
    uint64_t lastShiftTap_ = 0;
    double width_ = 0, height_ = 0;
};

} // namespace hotaru
