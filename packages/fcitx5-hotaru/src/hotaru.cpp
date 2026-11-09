// fcitx5 addon: an on-screen keyboard that lives inside fcitx.
//
// KWin keeps fcitx5 as its one input method and shows input-panel surfaces
// from it, on the desktop and on the lock screen alike. This addon opens one
// on fcitx's own connection to KWin and lets KWin decide when it is seen.
//
// It is also fcitx's on-screen keyboard user interface: once a finger
// touches it, fcitx switches to on-screen keyboard mode, classicui steps
// aside, and candidates come here to be drawn in the strip above the keys.
// A key on a physical keyboard switches back.

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <tuple>
#include <cairo.h>
#include <wayland-client.h>
#include <wayland_public.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/log.h>
#include <fcitx/action.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputmethodentry.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputmethodmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/menu.h>
#include <fcitx/statusarea.h>
#include <fcitx/userinterface.h>
#include <fcitx/userinterfacemanager.h>
#include "input-method-unstable-v1-client.h"
#include "keyboard.h"
#include "theme.h"
#include "xdg-output-unstable-v1-client.h"
// From fcitx5's source; see CMakeLists.txt.
#include "wl_surface.h"

namespace hotaru {

FCITX_DEFINE_LOG_CATEGORY(log, "hotaru");
#define HOTARU_DEBUG() FCITX_LOGC(::hotaru::log, Debug)
#define HOTARU_WARN() FCITX_LOGC(::hotaru::log, Warn)

class Addon;

// One shm buffer, freed when the compositor releases it.
struct Buffer {
    wl_buffer *buffer = nullptr;
    void *data = nullptr;
    size_t size = 0;

    static Buffer *create(wl_shm *shm, int width, int height) {
        const int stride = width * 4;
        const size_t size = size_t(stride) * height;
        int fd = memfd_create("hotaru", MFD_CLOEXEC);
        if (fd < 0 || ftruncate(fd, size) < 0) {
            if (fd >= 0) {
                close(fd);
            }
            return nullptr;
        }
        void *data = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED,
                          fd, 0);
        if (data == MAP_FAILED) {
            close(fd);
            return nullptr;
        }
        auto *pool = wl_shm_create_pool(shm, fd, size);
        auto *self = new Buffer;
        self->buffer = wl_shm_pool_create_buffer(pool, 0, width, height,
                                                 stride,
                                                 WL_SHM_FORMAT_ARGB8888);
        self->data = data;
        self->size = size;
        wl_shm_pool_destroy(pool);
        close(fd);
        static const wl_buffer_listener listener = {
            .release =
                [](void *data, wl_buffer *) {
                    delete static_cast<Buffer *>(data);
                },
        };
        wl_buffer_add_listener(self->buffer, &listener, self);
        return self;
    }

    ~Buffer() {
        wl_buffer_destroy(buffer);
        munmap(data, size);
    }
};

// Recently used emoji and kaomoji, one per line, kept across restarts.
std::string recentPath(const char *name) {
    const char *data = std::getenv("XDG_DATA_HOME");
    const char *home = std::getenv("HOME");
    std::string dir = data && *data ? data
                                    : std::string(home ? home : "") +
                                          "/.local/share";
    return dir + "/fcitx5/hotaru/" + name;
}

std::vector<std::string> loadRecent(const char *name) {
    std::vector<std::string> items;
    std::ifstream in(recentPath(name));
    for (std::string line; std::getline(in, line);) {
        if (!line.empty()) {
            items.push_back(line);
        }
    }
    return items;
}

void saveRecent(const std::vector<std::string> &emoji,
                const std::vector<std::string> &kaomoji) {
    std::filesystem::create_directories(
        std::filesystem::path(recentPath("x")).parent_path());
    for (auto [name, items] :
         {std::pair{"recent-emoji", &emoji},
          std::pair{"recent-kaomoji", &kaomoji}}) {
        std::ofstream out(recentPath(name));
        for (const auto &item : *items) {
            out << item << '\n';
        }
    }
}

// How far from each key's centre presses land, for moving the keys' hit areas
// to where the thumbs really go. Running totals per key and nothing else: a
// log in order would be everything that was typed.
class TouchStats {
public:
    TouchStats() {
        std::ifstream in(recentPath("touches.tsv"));
        std::string page, orientation, key;
        Sum s;
        while (in >> page >> orientation >> key >> s.n >> s.x >> s.y >> s.xx >>
               s.yy) {
            sums_[{page, orientation, key}] = s;
        }
    }
    ~TouchStats() { save(); }

    void add(const std::string &page, const char *rotation,
             const std::string &key, double dx, double dy) {
        auto &s = sums_[{page, rotation, key}];
        s.n++;
        s.x += dx;
        s.y += dy;
        s.xx += dx * dx;
        s.yy += dy * dy;
        if (++unsaved_ >= 20) {
            save();
        }
    }

private:
    struct Sum {
        long n = 0;
        double x = 0, y = 0, xx = 0, yy = 0;
    };

    void save() {
        if (!unsaved_) {
            return;
        }
        unsaved_ = 0;
        const std::filesystem::path path = recentPath("touches.tsv");
        std::error_code ec;
        std::filesystem::create_directories(path.parent_path(), ec);
        auto temp = path;
        temp += ".new";
        {
            std::ofstream out(temp);
            out.precision(12);
            for (const auto &[where, s] : sums_) {
                const auto &[page, orientation, key] = where;
                out << page << '\t' << orientation << '\t' << key << '\t'
                    << s.n << '\t' << s.x << '\t' << s.y << '\t' << s.xx
                    << '\t' << s.yy << '\n';
            }
        }
        std::filesystem::rename(temp, path, ec);
    }

    std::map<std::tuple<std::string, std::string, std::string>, Sum> sums_;
    int unsaved_ = 0;
};

// What the keyboard shows besides its keys, gathered from fcitx.
struct State {
    Candidates candidates;
    bool chinese = false;
    std::vector<std::string> imLabels;
    int imCurrent = -1;
    bool pad = false;
    bool hints = false;
    bool zhuyin = false;
    std::vector<MenuEntry> menu;
};

// fcitx's connection to KWin. Only the input method's own connection gets
// zwp_input_panel_v1, so connections without it are left alone.
class Connection {
public:
    Connection(Addon *addon, wl_display *display);
    ~Connection();

    bool hasPanel() const { return panel_ != nullptr; }
    bool shown() const { return surface_ != nullptr; }
    // Some text field has focus. Without one KWin won't show the panel, and
    // a buffer committed then is left on screen, drawn but dead to touch.
    void setFocused(bool focused);
    // The hide key: unmap until a text field is touched again.
    void userHide();
    void userShow();
    void setState(const State &state);

private:
    void global(wl_registry *registry, uint32_t name, const char *interface,
                uint32_t version);
    void seatCapabilities(uint32_t caps);
    void show();
    void hide();
    void draw();
    void press(int32_t id, double x, double y);
    void move(int32_t id, double x, double y);
    void lift(int32_t id);
    void cancel();
    void startRepeat(int32_t id);
    void startLongPress(int32_t id);
    void longPress(int32_t id);
    void perform(const Keyboard::Action &action);

    Addon *addon_;
    wl_display *display_;
    wl_registry *registry_ = nullptr;
    wl_compositor *compositor_ = nullptr;
    wl_shm *shm_ = nullptr;
    wl_seat *seat_ = nullptr;
    wl_touch *touch_ = nullptr;
    wl_pointer *pointer_ = nullptr;
    wl_output *output_ = nullptr;
    zxdg_output_manager_v1 *xdgOutputManager_ = nullptr;
    zxdg_output_v1 *xdgOutput_ = nullptr;
    zwp_input_panel_v1 *panel_ = nullptr;

    // Every surface on fcitx's connection must carry fcitx's WlSurface
    // wrapper: classicui reads it off any surface a touch or pointer event
    // names, and skips those whose userData() is empty.
    std::unique_ptr<fcitx::wayland::WlSurface> surface_;
    wl_surface *rawSurface() {
        return surface_ ? static_cast<wl_surface *>(*surface_) : nullptr;
    }
    zwp_input_panel_surface_v1 *panelSurface_ = nullptr;

    int32_t scale_ = 1;
    int32_t logicalWidth_ = 0, logicalHeight_ = 0;
    int32_t transform_ = WL_OUTPUT_TRANSFORM_NORMAL;
    int32_t width_ = 0, height_ = 0;
    bool userHidden_ = false;
    bool focused_ = false;

    // Every finger on the keyboard, by touch id; the mouse is one more.
    struct Finger {
        int key = -1;
        double x = 0, startX = 0;
        bool done = false;  // already typed: a later finger rolled over it
        bool popup = false; // holding opened the alternates
    };
    std::map<int32_t, Finger> fingers_;
    static constexpr int32_t Mouse = -100;
    double pointerX_ = 0, pointerY_ = 0;
    bool pointerDown_ = false;

    Keyboard keyboard_;
    Theme theme_;
    TouchStats touches_;
    bool privateField_ = false; // passwords and the like: nothing is counted
    // Backspace repeating and the long press timer, and whose they are.
    std::unique_ptr<fcitx::EventSourceTime> repeat_, longPress_;
    int32_t repeatFinger_ = 0, longPressFinger_ = 0;
};

class Addon : public fcitx::VirtualKeyboardUserInterface {
public:
    explicit Addon(fcitx::Instance *instance);
    ~Addon() override;

    fcitx::Instance *instance() { return instance_; }

    // UserInterface. Only used in on-screen keyboard mode; classicui has the
    // physical keyboard.
    void update(fcitx::UserInterfaceComponent component,
                fcitx::InputContext *ic) override;
    bool available() override;
    void suspend() override {}
    void resume() override { refresh(); }
    bool isVirtualKeyboardVisible() const override;
    // KWin decides when the panel is seen; these only undo the hide key.
    void showVirtualKeyboard() override;
    void hideVirtualKeyboard() override {}

    // Called by a connection: a finger is on the keyboard.
    void touched();
    void type(uint32_t sym);
    void selectCandidate(int index);
    // Put text in as is, past the input method: what's being spelled is
    // settled first, the way punctuation would.
    void commitText(const std::string &text);
    // A line break in the field rather than Enter, which chat apps take as
    // send.
    void newline();
    void toggleLanguage();
    // One from the current group's list, as the language key's row shows it.
    void switchInputMethod(int index);
    void activateMenuItem(int index);
    void refresh();

private:
    FCITX_ADDON_DEPENDENCY_LOADER(wayland, instance_->addonManager());

    void setFocused(bool focused);
    // The switches fcitx would list under Ctrl+~ / the tray icon.
    std::vector<fcitx::Action *> menuActions(fcitx::InputContext *ic);
    // rime's schemas, from its menu in the status area: name and action.
    // Only there while rime is the input method.
    std::vector<std::pair<std::string, fcitx::Action *>>
    rimeSchemas(fcitx::InputContext *ic);

    fcitx::Instance *instance_;
    State state_;
    bool hints_ = false;
    // What each label in the language key's row switches to: an input
    // method, and for rime which schema. rime's schema names are kept from
    // the last time it was on, so they still show while on EN.
    struct Choice {
        std::string im, schema;
    };
    std::vector<Choice> choices_;
    std::vector<std::string> rimeSchemaNames_;
    // Candidate list the strip's words came from, and how to reach each
    // word in it: through the whole list when it allows, else the page.
    std::shared_ptr<fcitx::CandidateList> candidateList_;
    bool bulk_ = false;
    // Menu entries past fcitx's own are hotaru's.
    std::vector<fcitx::Action *> menuActions_;
    std::unordered_map<wl_display *, std::unique_ptr<Connection>>
        connections_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::WaylandConnectionCreated>>
        created_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::WaylandConnectionClosed>>
        closed_;
    std::vector<std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>>
        events_;
    std::unique_ptr<fcitx::EventSource> focusCheck_;
};

Connection::Connection(Addon *addon, wl_display *display)
    : addon_(addon), display_(display) {
    Keyboard::loadData(HOTARU_DATADIR);
    keyboard_.setRecent(loadRecent("recent-emoji"),
                        loadRecent("recent-kaomoji"));
    static const wl_registry_listener listener = {
        .global =
            [](void *data, wl_registry *registry, uint32_t name,
               const char *interface, uint32_t version) {
                static_cast<Connection *>(data)->global(registry, name,
                                                         interface, version);
            },
        .global_remove = [](void *, wl_registry *, uint32_t) {},
    };
    registry_ = wl_display_get_registry(display_);
    wl_registry_add_listener(registry_, &listener, this);
    wl_display_flush(display_);
}

Connection::~Connection() {
    hide();
    if (touch_) {
        wl_touch_release(touch_);
    }
    if (pointer_) {
        wl_pointer_release(pointer_);
    }
    if (xdgOutput_) {
        zxdg_output_v1_destroy(xdgOutput_);
    }
    if (panel_) {
        zwp_input_panel_v1_destroy(panel_);
    }
    // The display itself is going away with fcitx's connection; the
    // remaining proxies die with it.
    wl_registry_destroy(registry_);
}

void Connection::global(wl_registry *registry, uint32_t name,
                        const char *interface, uint32_t version) {
    const std::string_view iface(interface);
    if (iface == wl_compositor_interface.name) {
        compositor_ = static_cast<wl_compositor *>(wl_registry_bind(
            registry, name, &wl_compositor_interface, std::min(version, 4u)));
    } else if (iface == wl_shm_interface.name) {
        shm_ = static_cast<wl_shm *>(
            wl_registry_bind(registry, name, &wl_shm_interface, 1));
    } else if (iface == wl_seat_interface.name && !seat_) {
        seat_ = static_cast<wl_seat *>(wl_registry_bind(
            registry, name, &wl_seat_interface, std::min(version, 5u)));
        static const wl_seat_listener listener = {
            .capabilities =
                [](void *data, wl_seat *, uint32_t caps) {
                    static_cast<Connection *>(data)->seatCapabilities(caps);
                },
            .name = [](void *, wl_seat *, const char *) {},
        };
        wl_seat_add_listener(seat_, &listener, this);
    } else if (iface == wl_output_interface.name && !output_) {
        // saren has one screen; the keyboard goes on the first output.
        output_ = static_cast<wl_output *>(wl_registry_bind(
            registry, name, &wl_output_interface, std::min(version, 2u)));
        static const wl_output_listener listener = {
            .geometry =
                [](void *data, wl_output *, int32_t, int32_t, int32_t, int32_t,
                   int32_t, const char *, const char *, int32_t transform) {
                    static_cast<Connection *>(data)->transform_ = transform;
                },
            .mode = [](void *, wl_output *, uint32_t, int32_t, int32_t,
                       int32_t) {},
            .done = [](void *data,
                       wl_output *) { static_cast<Connection *>(data)->draw(); },
            .scale =
                [](void *data, wl_output *, int32_t scale) {
                    static_cast<Connection *>(data)->scale_ = scale;
                },
            .name = nullptr,
            .description = nullptr,
        };
        wl_output_add_listener(output_, &listener, this);
    } else if (iface == zxdg_output_manager_v1_interface.name) {
        xdgOutputManager_ = static_cast<zxdg_output_manager_v1 *>(
            wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface,
                             std::min(version, 3u)));
    } else if (iface == zwp_input_panel_v1_interface.name) {
        panel_ = static_cast<zwp_input_panel_v1 *>(
            wl_registry_bind(registry, name, &zwp_input_panel_v1_interface, 1));
        HOTARU_DEBUG() << "input panel available";
        addon_->instance()->userInterfaceManager().updateAvailability();
    }

    if (output_ && xdgOutputManager_ && !xdgOutput_) {
        xdgOutput_ =
            zxdg_output_manager_v1_get_xdg_output(xdgOutputManager_, output_);
        static const zxdg_output_v1_listener listener = {
            .logical_position = [](void *, zxdg_output_v1 *, int32_t,
                                   int32_t) {},
            .logical_size =
                [](void *data, zxdg_output_v1 *, int32_t w, int32_t h) {
                    auto *self = static_cast<Connection *>(data);
                    self->logicalWidth_ = w;
                    self->logicalHeight_ = h;
                },
            .done = [](void *, zxdg_output_v1 *) {},
            .name = [](void *, zxdg_output_v1 *, const char *) {},
            .description = [](void *, zxdg_output_v1 *, const char *) {},
        };
        zxdg_output_v1_add_listener(xdgOutput_, &listener, this);
    }
    if (panel_ && !surface_) {
        focused_ = addon_->instance()->lastFocusedInputContext() != nullptr;
        show();
    }
}

void Connection::seatCapabilities(uint32_t caps) {
    if ((caps & WL_SEAT_CAPABILITY_TOUCH) && !touch_) {
        touch_ = wl_seat_get_touch(seat_);
        static const wl_touch_listener listener = {
            .down =
                [](void *data, wl_touch *, uint32_t, uint32_t,
                   wl_surface *surface, int32_t id, wl_fixed_t x,
                   wl_fixed_t y) {
                    auto *self = static_cast<Connection *>(data);
                    if (surface != self->rawSurface()) {
                        return;
                    }
                    self->press(id, wl_fixed_to_double(x),
                                wl_fixed_to_double(y));
                },
            .up =
                [](void *data, wl_touch *, uint32_t, uint32_t, int32_t id) {
                    static_cast<Connection *>(data)->lift(id);
                },
            .motion =
                [](void *data, wl_touch *, uint32_t, int32_t id,
                   wl_fixed_t x, wl_fixed_t y) {
                    static_cast<Connection *>(data)->move(
                        id, wl_fixed_to_double(x), wl_fixed_to_double(y));
                },
            .frame = [](void *, wl_touch *) {},
            .cancel =
                [](void *data, wl_touch *) {
                    static_cast<Connection *>(data)->cancel();
                },
            .shape = [](void *, wl_touch *, int32_t, wl_fixed_t,
                        wl_fixed_t) {},
            .orientation = [](void *, wl_touch *, int32_t, wl_fixed_t) {},
        };
        wl_touch_add_listener(touch_, &listener, this);
    }
    if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer_) {
        pointer_ = wl_seat_get_pointer(seat_);
        static const wl_pointer_listener listener = {
            .enter =
                [](void *data, wl_pointer *, uint32_t, wl_surface *,
                   wl_fixed_t x, wl_fixed_t y) {
                    auto *self = static_cast<Connection *>(data);
                    self->pointerX_ = wl_fixed_to_double(x);
                    self->pointerY_ = wl_fixed_to_double(y);
                },
            .leave =
                [](void *data, wl_pointer *, uint32_t, wl_surface *) {
                    auto *self = static_cast<Connection *>(data);
                    if (self->pointerDown_) {
                        self->pointerDown_ = false;
                        self->cancel();
                    }
                },
            .motion =
                [](void *data, wl_pointer *, uint32_t, wl_fixed_t x,
                   wl_fixed_t y) {
                    auto *self = static_cast<Connection *>(data);
                    self->pointerX_ = wl_fixed_to_double(x);
                    self->pointerY_ = wl_fixed_to_double(y);
                    if (self->pointerDown_) {
                        self->move(Mouse, self->pointerX_, self->pointerY_);
                    }
                },
            .button =
                [](void *data, wl_pointer *, uint32_t, uint32_t,
                   uint32_t button, uint32_t state) {
                    auto *self = static_cast<Connection *>(data);
                    if (button != 0x110) { // BTN_LEFT
                        return;
                    }
                    if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
                        self->pointerDown_ = true;
                        self->press(Mouse, self->pointerX_, self->pointerY_);
                    } else if (self->pointerDown_) {
                        self->pointerDown_ = false;
                        self->lift(Mouse);
                    }
                },
            .axis = [](void *, wl_pointer *, uint32_t, uint32_t,
                       wl_fixed_t) {},
            .frame = [](void *, wl_pointer *) {},
            .axis_source = [](void *, wl_pointer *, uint32_t) {},
            .axis_stop = [](void *, wl_pointer *, uint32_t, uint32_t) {},
            .axis_discrete = [](void *, wl_pointer *, uint32_t, int32_t) {},
            .axis_value120 = nullptr,
            .axis_relative_direction = nullptr,
        };
        wl_pointer_add_listener(pointer_, &listener, this);
    }
}

void Connection::setFocused(bool focused) {
    if (focused == focused_) {
        return;
    }
    focused_ = focused;
    if (focused) {
        show();
    } else {
        // The hide key lasts until the next text field, not forever.
        userHidden_ = false;
        hide();
    }
}

void Connection::userHide() {
    userHidden_ = true;
    hide();
}

void Connection::userShow() {
    if (!userHidden_) {
        return;
    }
    userHidden_ = false;
    show();
}

void Connection::setState(const State &state) {
    keyboard_.setCandidates(state.candidates);
    keyboard_.setLanguage(state.chinese);
    keyboard_.setInputMethods(state.imLabels, state.imCurrent);
    keyboard_.setPad(state.pad);
    privateField_ = state.pad;
    keyboard_.setZhuyin(state.zhuyin);
    keyboard_.setHints(state.hints);
    keyboard_.setMenu(state.menu);
    draw();
}

void Connection::show() {
    if (!focused_ || userHidden_ || surface_ || !panel_ || !compositor_ ||
        !shm_ || !output_) {
        return;
    }
    theme_ = Theme::load();
    keyboard_.setFont(theme_.font);
    keyboard_.reset();
    surface_ = std::make_unique<fcitx::wayland::WlSurface>(
        wl_compositor_create_surface(compositor_));
    panelSurface_ =
        zwp_input_panel_v1_get_input_panel_surface(panel_, rawSurface());
    zwp_input_panel_surface_v1_set_toplevel(
        panelSurface_, output_,
        ZWP_INPUT_PANEL_SURFACE_V1_POSITION_CENTER_BOTTOM);
    width_ = height_ = 0;
    draw();
    HOTARU_DEBUG() << "shown";
}

void Connection::hide() {
    repeat_.reset();
    longPress_.reset();
    fingers_.clear();
    pointerDown_ = false;
    if (panelSurface_) {
        zwp_input_panel_surface_v1_destroy(panelSurface_);
        panelSurface_ = nullptr;
    }
    if (surface_) {
        surface_.reset();
        wl_display_flush(display_);
        HOTARU_DEBUG() << "hidden";
    }
}

void Connection::draw() {
    if (!surface_) {
        return;
    }
    const int lw = logicalWidth_ > 0 ? logicalWidth_ : 1280;
    const int lh = logicalHeight_ > 0 ? logicalHeight_ : 800;
    // Tall enough for a thumb, short enough to leave the text visible on
    // the Pocket's small screen, the strip included.
    const int w = lw;
    const int h = std::min(int(lh * 0.38), int(lw * 0.34));
    if (w != width_ || h != height_) {
        width_ = w;
        height_ = h;
        keyboard_.resize(w, h);
    }

    auto *buffer = Buffer::create(shm_, w * scale_, h * scale_);
    if (!buffer) {
        HOTARU_WARN() << "cannot allocate a buffer";
        return;
    }
    auto *image = cairo_image_surface_create_for_data(
        static_cast<unsigned char *>(buffer->data), CAIRO_FORMAT_ARGB32,
        w * scale_, h * scale_, w * scale_ * 4);
    auto *cr = cairo_create(image);
    cairo_scale(cr, scale_, scale_);
    keyboard_.paint(cr, theme_);
    cairo_destroy(cr);
    cairo_surface_destroy(image);

    auto *surface = rawSurface();
    wl_surface_set_buffer_scale(surface, scale_);
    wl_surface_attach(surface, buffer->buffer, 0, 0);
    wl_surface_damage(surface, 0, 0, w, h);
    wl_surface_commit(surface);
    wl_display_flush(display_);
}

void Connection::press(int32_t id, double x, double y) {
    addon_->touched();
    // While the alternates are up, the finger holding them is the only one
    // that counts.
    if (keyboard_.popupOpen()) {
        return;
    }
    // A key still under an earlier finger types now, in the order the
    // fingers landed. Shift and space are held on purpose, so they stay.
    for (auto &[other, finger] : fingers_) {
        if (finger.done || !keyboard_.isChar(finger.key)) {
            continue;
        }
        if (longPressFinger_ == other) {
            longPress_.reset();
        }
        perform(keyboard_.release(finger.key));
        finger.done = true;
    }
    const int key = keyboard_.keyAt(x, y);
    if (const auto at = keyboard_.landing(key, x, y);
        at && id != Mouse && !privateField_) {
        static const char *const rotations[] = {"0", "90", "180", "270"};
        touches_.add(at->page, rotations[transform_ & 3], at->key, at->dx,
                     at->dy);
    }
    fingers_[id] = {key, x, x};
    keyboard_.hold(key);
    if (keyboard_.repeats(key)) {
        addon_->type(0xff08);
        startRepeat(id);
    } else if (keyboard_.isSpace(key)) {
        keyboard_.dragSpace(x);
    } else if (keyboard_.isShift(key)) {
        keyboard_.shiftDown();
    }
    if (keyboard_.longPresses(key)) {
        startLongPress(id);
    }
    draw();
}

void Connection::move(int32_t id, double x, double y) {
    auto it = fingers_.find(id);
    if (it == fingers_.end() || it->second.done) {
        return;
    }
    auto &finger = it->second;
    finger.x = x;
    // A swipe across the emoji: the next or previous screenful. The finger
    // types nothing after.
    if (keyboard_.inPicker() && keyboard_.isCell(finger.key) &&
        std::abs(x - finger.startX) > keyboard_.cellWidth() * 0.6) {
        keyboard_.unhold(finger.key);
        keyboard_.turnPickerPage(x < finger.startX ? 1 : -1);
        finger.done = true;
        draw();
        return;
    }
    if (finger.popup) {
        keyboard_.popupMove(x, y);
        draw();
        return;
    }
    if (keyboard_.isSpace(finger.key)) {
        // Sliding along space moves the cursor, as on a phone.
        for (auto sym : keyboard_.dragSpace(x)) {
            addon_->type(sym);
        }
        return;
    }
    int key = keyboard_.keyAt(x, y);
    // Sliding off backspace stops deleting, and lands on nothing.
    if (keyboard_.repeats(key) && key != finger.key) {
        key = -1;
    }
    if (key == finger.key) {
        return;
    }
    // Sliding to the neighbouring key picks that one instead.
    if (repeatFinger_ == id) {
        repeat_.reset();
    }
    if (longPressFinger_ == id) {
        longPress_.reset();
    }
    if (keyboard_.isShift(finger.key)) {
        keyboard_.shiftLeave();
    }
    keyboard_.unhold(finger.key);
    finger.key = key;
    keyboard_.hold(key);
    if (keyboard_.longPresses(key)) {
        startLongPress(id);
    }
    draw();
}

void Connection::lift(int32_t id) {
    auto it = fingers_.find(id);
    if (it == fingers_.end()) {
        return;
    }
    const auto finger = it->second;
    fingers_.erase(it);
    if (repeatFinger_ == id) {
        repeat_.reset();
    }
    if (longPressFinger_ == id) {
        longPress_.reset();
    }
    keyboard_.unhold(finger.key);
    if (finger.done) {
        draw();
        return;
    }
    if (finger.popup) {
        auto text = keyboard_.closePopup();
        if (keyboard_.isLang(finger.key)) {
            addon_->switchInputMethod(keyboard_.popupPicked());
            draw();
            return;
        }
        if (text.empty()) {
            // Lifted without sliding into the row: a plain tap.
            perform(keyboard_.release(finger.key));
            draw();
            return;
        }
        if (text == "\n") {
            addon_->newline();
            draw();
            return;
        }
        // A symbol types like the key it stands for, so rime still turns it
        // full width; letters and the rest go in as they are. Under 注音 rime
        // would read a digit or / as a symbol, so those go in as they are too.
        if (!keyboard_.zhuyin() && text.size() == 1 &&
            !std::isalpha(static_cast<unsigned char>(text[0]))) {
            addon_->type(static_cast<unsigned char>(text[0]));
        } else {
            addon_->commitText(text);
        }
        draw();
        return;
    }
    const auto action = keyboard_.release(finger.key);
    if (action.hide) {
        // Unmapping is all it takes, as in plasma-keyboard: KWin drops a
        // panel without a buffer. Telling KWin to deactivate doesn't stick
        // while the text field keeps focus.
        userHide();
        return;
    }
    perform(action);
    draw();
}

void Connection::perform(const Keyboard::Action &action) {
    // Each of these may change what the strip shows; fcitx calls back into
    // update(), which redraws.
    if (action.sym) {
        addon_->type(action.sym);
    }
    if (!action.text.empty()) {
        addon_->commitText(action.text);
    }
    if (action.recentChanged) {
        saveRecent(keyboard_.recentEmoji(), keyboard_.recentKaomoji());
    }
    if (action.candidate >= 0) {
        addon_->selectCandidate(action.candidate);
    }
    if (action.toggleLanguage) {
        addon_->toggleLanguage();
    }
    if (action.menuItem >= 0) {
        addon_->activateMenuItem(action.menuItem);
    }
    if (action.menuOpened) {
        addon_->refresh();
    }
}

void Connection::cancel() {
    repeat_.reset();
    longPress_.reset();
    for (auto &[id, finger] : fingers_) {
        keyboard_.unhold(finger.key);
    }
    fingers_.clear();
    keyboard_.closePopup();
    keyboard_.release(-1);
    keyboard_.shiftLeave();
    draw();
}

void Connection::startRepeat(int32_t id) {
    auto &loop = addon_->instance()->eventLoop();
    repeatFinger_ = id;
    repeat_ = loop.addTimeEvent(
        CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 400000, 0,
        [this](fcitx::EventSourceTime *source, uint64_t) {
            addon_->type(0xff08);
            source->setNextInterval(60000);
            source->setOneShot();
            return true;
        });
}

void Connection::startLongPress(int32_t id) {
    auto &loop = addon_->instance()->eventLoop();
    longPressFinger_ = id;
    // Gboard's default: long enough not to catch a slow tap.
    longPress_ = loop.addTimeEvent(
        CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 350000, 0,
        [this, id](fcitx::EventSourceTime *, uint64_t) {
            longPress(id);
            return true;
        });
}

void Connection::longPress(int32_t id) {
    auto it = fingers_.find(id);
    if (it == fingers_.end() || it->second.done) {
        return;
    }
    auto &finger = it->second;
    keyboard_.openPopup(finger.key);
    finger.popup = true;
    draw();
}

Addon::Addon(fcitx::Instance *instance) : instance_(instance) {
    auto *wl = wayland();
    if (!wl) {
        return;
    }
    created_ = wl->call<fcitx::IWaylandModule::addConnectionCreatedCallback>(
        [this](const std::string &, wl_display *display,
               fcitx::FocusGroup *) {
            connections_[display] = std::make_unique<Connection>(this, display);
        });
    closed_ = wl->call<fcitx::IWaylandModule::addConnectionClosedCallback>(
        [this](const std::string &, wl_display *display) {
            connections_.erase(display);
            instance_->userInterfaceManager().updateAvailability();
        });

    // Touching a text field again, or the lock screen's own keyboard button,
    // focuses it anew or moves its cursor; either brings a hidden keyboard
    // back. plasma-keyboard does the same.
    for (auto type : {fcitx::EventType::InputContextFocusIn,
                      fcitx::EventType::InputContextSurroundingTextUpdated}) {
        events_.push_back(instance_->watchEvent(
            type, fcitx::EventWatcherPhase::PostInputMethod,
            [this](fcitx::Event &) {
                for (auto &[display, conn] : connections_) {
                    conn->userShow();
                }
            }));
    }
    // Map the panel only while a text field has focus. Focus out comes
    // before the next focus in when it moves between fields, so look once
    // things have settled.
    events_.push_back(instance_->watchEvent(
        fcitx::EventType::InputContextFocusIn,
        fcitx::EventWatcherPhase::PreInputMethod,
        [this](fcitx::Event &) { setFocused(true); }));
    // What each field says it is, to see which ones admit to taking
    // several lines.
    events_.push_back(instance_->watchEvent(
        fcitx::EventType::InputContextCapabilityChanged,
        fcitx::EventWatcherPhase::PostInputMethod, [](fcitx::Event &event) {
            auto *ic = static_cast<fcitx::InputContextEvent &>(event)
                           .inputContext();
            FCITX_LOGC(::hotaru::log, Info)
                << "field " << ic->program() << " caps 0x" << std::hex
                << ic->capabilityFlags().toInteger();
        }));
    events_.push_back(instance_->watchEvent(
        fcitx::EventType::InputContextFocusOut,
        fcitx::EventWatcherPhase::PostInputMethod, [this](fcitx::Event &) {
            focusCheck_ = instance_->eventLoop().addDeferEvent(
                [this](fcitx::EventSource *) {
                    setFocused(instance_->lastFocusedInputContext() !=
                               nullptr);
                    focusCheck_.reset();
                    return true;
                });
        }));
    // Which language the keys type in, and rime's switches, change with the
    // focused field and the input method.
    // The field says it's a password only once focused: the content type
    // comes after the focus.
    for (auto type : {fcitx::EventType::InputContextFocusIn,
                      fcitx::EventType::InputContextSwitchInputMethod,
                      fcitx::EventType::InputContextUpdateUI,
                      fcitx::EventType::InputContextCapabilityChanged}) {
        events_.push_back(instance_->watchEvent(
            type, fcitx::EventWatcherPhase::PostInputMethod,
            [this](fcitx::Event &) { refresh(); }));
    }
    // A key from a real keyboard hands things back to classicui, as fcitx's
    // own D-Bus virtual keyboard does.
    events_.push_back(instance_->watchEvent(
        fcitx::EventType::InputContextKeyEvent,
        fcitx::EventWatcherPhase::PreInputMethod, [this](fcitx::Event &event) {
            auto &keyEvent = static_cast<fcitx::KeyEvent &>(event);
            if (keyEvent.origKey().states().test(fcitx::KeyState::Virtual)) {
                return;
            }
            instance_->setInputMethodMode(
                fcitx::InputMethodMode::PhysicalKeyboard);
        }));
}

Addon::~Addon() = default;

void Addon::setFocused(bool focused) {
    for (auto &[display, conn] : connections_) {
        conn->setFocused(focused);
    }
}

bool Addon::available() {
    for (auto &[display, conn] : connections_) {
        if (conn->hasPanel()) {
            return true;
        }
    }
    return false;
}

bool Addon::isVirtualKeyboardVisible() const {
    for (const auto &[display, conn] : connections_) {
        if (conn->shown()) {
            return true;
        }
    }
    return false;
}

void Addon::showVirtualKeyboard() {
    for (auto &[display, conn] : connections_) {
        conn->userShow();
    }
}

void Addon::update(fcitx::UserInterfaceComponent component,
                   fcitx::InputContext *) {
    if (component == fcitx::UserInterfaceComponent::InputPanel) {
        refresh();
    }
}

void Addon::touched() {
    if (instance_->inputMethodMode() ==
        fcitx::InputMethodMode::OnScreenKeyboard) {
        return;
    }
    HOTARU_DEBUG() << "on-screen keyboard mode";
    instance_->setInputMethodMode(fcitx::InputMethodMode::OnScreenKeyboard);
    // Whatever classicui was showing moves into the strip.
    if (auto *ic = instance_->lastFocusedInputContext()) {
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel,
                                true);
    }
}

std::vector<fcitx::Action *>
Addon::menuActions(fcitx::InputContext *ic) {
    std::vector<fcitx::Action *> result;
    std::function<void(const std::vector<fcitx::Action *> &, bool)> collect =
        [&](const std::vector<fcitx::Action *> &actions, bool rimeSchemas) {
            bool first = true;
            for (auto *action : actions) {
                if (action->isSeparator()) {
                    continue;
                }
                const auto &name = action->name();
                // Deploying and syncing are maintenance, not something to
                // tap by accident while typing.
                if (name == "fcitx-rime-deploy" || name == "fcitx-rime-sync") {
                    continue;
                }
                // rime's schema menu opens with "Latin Mode", rime's own
                // English, a second one beside the 中/EN key's. Two English
                // modes are easy to mix up; leave it to the key.
                if (rimeSchemas && first) {
                    first = false;
                    continue;
                }
                // An action with a menu (rime's schemas, say) is a heading;
                // what's under it are the switches.
                if (auto *menu = action->menu()) {
                    collect(menu->actions(), name == "fcitx-rime-im");
                } else if (!action->shortText(ic).empty()) {
                    result.push_back(action);
                }
            }
        };
    collect(ic->statusArea().allActions(), false);
    return result;
}

void Addon::refresh() {
    State state;
    auto *ic = instance_->lastFocusedInputContext();
    if (ic) {
        const auto *entry = instance_->inputMethodEntry(ic);
        state.chinese = entry && !entry->isKeyboard();
        const bool rime = entry && entry->uniqueName() == "rime";
        // rime's schema now, by its name, e.g. 注音·臺灣正體.
        std::string schema;
        if (rime) {
            if (auto *engine = instance_->inputMethodEngine(ic)) {
                schema = engine->subMode(*entry, *ic);
            }
            auto schemas = rimeSchemas(ic);
            if (!schemas.empty()) {
                rimeSchemaNames_.clear();
                for (const auto &[name, action] : schemas) {
                    rimeSchemaNames_.push_back(name);
                }
            }
        }
        state.zhuyin = schema.find("注音") != std::string::npos;
        choices_.clear();
        const auto &group = instance_->inputMethodManager().currentGroup();
        for (const auto &item : group.inputMethodList()) {
            const auto *e =
                instance_->inputMethodManager().entry(item.name());
            if (!e) {
                continue;
            }
            if (e->uniqueName() == "rime" && !rimeSchemaNames_.empty()) {
                // One label per schema: 小鶴雙拼 is 中, 注音 is 注.
                for (const auto &name : rimeSchemaNames_) {
                    if (e == entry && name == schema) {
                        state.imCurrent = state.imLabels.size();
                    }
                    state.imLabels.push_back(
                        name.find("注音") != std::string::npos ? "注" : "中");
                    choices_.push_back({e->uniqueName(), name});
                }
                if (e == entry && state.imCurrent < 0) {
                    // On rime's own English, or a schema we didn't list.
                    state.imCurrent = state.imLabels.size() - 1;
                }
                continue;
            }
            if (e == entry) {
                state.imCurrent = state.imLabels.size();
            }
            // Their own labels read backwards here: rime says ㄓ, chewing 酷.
            static const std::map<std::string, std::string> names = {
                {"rime", "中"}, {"chewing", "注"}, {"mozc", "あ"}};
            auto it = names.find(e->uniqueName());
            state.imLabels.push_back(e->isKeyboard()    ? "EN"
                                     : it != names.end() ? it->second
                                                         : e->label());
            choices_.push_back({e->uniqueName(), ""});
        }
        // Passwords and digits get the number pad. KDE's lock screen marks
        // its field only as sensitive, not as a password.
        const auto caps = ic->capabilityFlags();
        state.pad = caps.test(fcitx::CapabilityFlag::Password) ||
                    caps.test(fcitx::CapabilityFlag::Sensitive) ||
                    caps.test(fcitx::CapabilityFlag::Digit) ||
                    caps.test(fcitx::CapabilityFlag::Number) ||
                    caps.test(fcitx::CapabilityFlag::Dialable);

        menuActions_ = menuActions(ic);
        for (auto *action : menuActions_) {
            state.menu.push_back(
                {action->shortText(ic),
                 action->isCheckable() && action->isChecked(ic)});
        }
        if (state.chinese && !state.zhuyin) {
            state.menu.push_back({"双拼提示", hints_});
        }
        // The hints are 小鶴雙拼's; other input methods have their own keys.
        state.hints = hints_ && rime && !state.zhuyin;

        // Candidates only while fcitx has handed them to us; in physical
        // keyboard mode they're classicui's.
        candidateList_.reset();
        bulk_ = false;
        if (instance_->inputMethodMode() ==
            fcitx::InputMethodMode::OnScreenKeyboard) {
            auto &panel = ic->inputPanel();
            state.candidates.preedit =
                instance_->outputFilter(ic, panel.preedit()).toString();
            if (auto list = panel.candidateList()) {
                candidateList_ = list;
                auto add = [&](const fcitx::CandidateWord &candidate) {
                    state.candidates.words.push_back(
                        instance_->outputFilter(ic, candidate.text())
                            .toString());
                };
                // The whole list, not just rime's page of five, so the
                // strip can fill its width. rime doesn't know how long it
                // is and throws past the end.
                if (auto *all = list->toBulk()) {
                    bulk_ = true;
                    const int total = all->totalSize();
                    const int limit = total >= 0 ? std::min(total, 60) : 60;
                    for (int i = 0; i < limit; i++) {
                        try {
                            add(all->candidateFromAll(i));
                        } catch (...) {
                            break;
                        }
                    }
                } else {
                    for (int i = 0; i < list->size(); i++) {
                        add(list->candidate(i));
                    }
                }
                // Space picks the cursor's candidate; the page's own index
                // is its index in the whole list when the page is the first.
                const int cursor = list->cursorIndex();
                state.candidates.cursor = cursor >= 0 ? cursor : 0;
                if (bulk_) {
                    if (auto *pageable = list->toPageable();
                        pageable && pageable->currentPage() > 0) {
                        state.candidates.cursor +=
                            pageable->currentPage() * list->size();
                    }
                }
            }
        }
    }
    for (auto &[display, conn] : connections_) {
        conn->setState(state);
    }
    state_ = std::move(state);
}

void Addon::type(uint32_t sym) {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic) {
        return;
    }
    // Through the input method, so rime gets the letters. Marked virtual so
    // the watcher above doesn't take it for a physical keyboard.
    const fcitx::Key key(static_cast<fcitx::KeySym>(sym),
                         fcitx::KeyStates(fcitx::KeyState::Virtual));
    fcitx::KeyEvent press(ic, key, false);
    if (!ic->keyEvent(press)) {
        // Nobody wanted it: straight to the app. The wayland frontend turns
        // a key without a keycode into zwp_input_method_context_v1.keysym,
        // which is what the lock screen's password field reads.
        ic->forwardKey(fcitx::Key(static_cast<fcitx::KeySym>(sym)));
    }
    fcitx::KeyEvent release(ic, key, true);
    ic->keyEvent(release);
}

void Addon::selectCandidate(int index) {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic || !candidateList_ || index < 0) {
        return;
    }
    // Hold on: selecting replaces the list under us.
    auto list = candidateList_;
    try {
        if (bulk_) {
            list->toBulk()->candidateFromAll(index).select(ic);
        } else if (index < list->size()) {
            list->candidate(index).select(ic);
        }
    } catch (...) {
    }
}

void Addon::commitText(const std::string &text) {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic) {
        return;
    }
    if (candidateList_ && !state_.candidates.words.empty()) {
        selectCandidate(state_.candidates.cursor);
    }
    ic->commitString(text);
}

void Addon::newline() {
    // The line break goes in as text, which no app reads as send. Neither
    // the Multiline hint (Telegram and Chrome don't set it) nor Shift+Enter
    // (KWin drops the shift on its way to text-input-v3 clients) works.
    commitText("\n");
}

std::vector<std::pair<std::string, fcitx::Action *>>
Addon::rimeSchemas(fcitx::InputContext *ic) {
    std::vector<std::pair<std::string, fcitx::Action *>> result;
    for (auto *action : ic->statusArea().allActions()) {
        auto *menu = action->menu();
        if (action->name() != "fcitx-rime-im" || !menu) {
            continue;
        }
        bool first = true;
        for (auto *schema : menu->actions()) {
            if (schema->isSeparator()) {
                continue;
            }
            // Latin Mode, rime's own English, heads the list.
            if (first) {
                first = false;
                continue;
            }
            // Deploy and sync sit under the same menu, after a separator.
            const auto &name = schema->name();
            if (name == "fcitx-rime-deploy" || name == "fcitx-rime-sync") {
                continue;
            }
            result.emplace_back(schema->shortText(ic), schema);
        }
    }
    return result;
}

void Addon::switchInputMethod(int index) {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic || index < 0 || size_t(index) >= choices_.size()) {
        return;
    }
    const auto choice = choices_[index];
    instance_->setCurrentInputMethod(ic, choice.im, false);
    if (choice.schema.empty()) {
        return;
    }
    for (const auto &[name, action] : rimeSchemas(ic)) {
        if (name == choice.schema) {
            action->activate(ic);
            break;
        }
    }
    refresh();
}

void Addon::toggleLanguage() {
    // Between the keyboard layout and rime, the way Win+Space does on saren.
    instance_->toggle();
}

void Addon::activateMenuItem(int index) {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic || index < 0) {
        return;
    }
    if (size_t(index) < menuActions_.size()) {
        menuActions_[index]->activate(ic);
    } else {
        hints_ = !hints_;
    }
    refresh();
}

class Factory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new Addon(manager->instance());
    }
};

} // namespace hotaru

FCITX_ADDON_FACTORY_V2(hotaru, hotaru::Factory);
