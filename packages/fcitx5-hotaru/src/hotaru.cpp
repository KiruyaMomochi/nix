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
#include <functional>
#include <memory>
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

// What the keyboard shows besides its keys, gathered from fcitx.
struct State {
    Candidates candidates;
    bool chinese = false;
    std::string scriptLabel;
};

// fcitx's connection to KWin. Only the input method's own connection gets
// zwp_input_panel_v1, so connections without it are left alone.
class Connection {
public:
    Connection(Addon *addon, wl_display *display);
    ~Connection();

    bool hasPanel() const { return panel_ != nullptr; }
    bool shown() const { return surface_ != nullptr; }
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
    void press(double x, double y);
    void move(double x, double y);
    void lift();
    void cancel();
    void startRepeat();

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
    int32_t width_ = 0, height_ = 0;
    bool userHidden_ = false;

    int32_t touchId_ = -1;
    double pointerX_ = 0, pointerY_ = 0;
    bool pointerDown_ = false;

    Keyboard keyboard_;
    Theme theme_;
    std::unique_ptr<fcitx::EventSourceTime> repeat_;
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
    void turnPage(int direction);
    void toggleLanguage();
    void toggleScript();

private:
    FCITX_ADDON_DEPENDENCY_LOADER(wayland, instance_->addonManager());

    void refresh();
    fcitx::Action *scriptAction(fcitx::InputContext *ic);

    fcitx::Instance *instance_;
    State state_;
    // Candidate positions on the page that made it into the strip.
    std::vector<int> candidateIndex_;
    std::unordered_map<wl_display *, std::unique_ptr<Connection>>
        connections_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::WaylandConnectionCreated>>
        created_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::WaylandConnectionClosed>>
        closed_;
    std::vector<std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>>
        events_;
};

Connection::Connection(Addon *addon, wl_display *display)
    : addon_(addon), display_(display) {
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
            .geometry = [](void *, wl_output *, int32_t, int32_t, int32_t,
                           int32_t, int32_t, const char *, const char *,
                           int32_t) {},
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
                    if (surface != self->rawSurface() || self->touchId_ >= 0) {
                        return;
                    }
                    self->touchId_ = id;
                    self->press(wl_fixed_to_double(x), wl_fixed_to_double(y));
                },
            .up =
                [](void *data, wl_touch *, uint32_t, uint32_t, int32_t id) {
                    auto *self = static_cast<Connection *>(data);
                    if (id == self->touchId_) {
                        self->touchId_ = -1;
                        self->lift();
                    }
                },
            .motion =
                [](void *data, wl_touch *, uint32_t, int32_t id,
                   wl_fixed_t x, wl_fixed_t y) {
                    auto *self = static_cast<Connection *>(data);
                    if (id == self->touchId_) {
                        self->move(wl_fixed_to_double(x),
                                   wl_fixed_to_double(y));
                    }
                },
            .frame = [](void *, wl_touch *) {},
            .cancel =
                [](void *data, wl_touch *) {
                    auto *self = static_cast<Connection *>(data);
                    self->touchId_ = -1;
                    self->cancel();
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
                        self->move(self->pointerX_, self->pointerY_);
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
                        self->press(self->pointerX_, self->pointerY_);
                    } else if (self->pointerDown_) {
                        self->pointerDown_ = false;
                        self->lift();
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
    keyboard_.setLanguage(state.chinese, state.scriptLabel);
    draw();
}

void Connection::show() {
    if (userHidden_ || surface_ || !panel_ || !compositor_ || !shm_ ||
        !output_) {
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
    touchId_ = -1;
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
    // Tall enough for a thumb, short enough to leave the text visible:
    // under half of a landscape screen, the strip included.
    const int w = lw;
    const int h = std::min(int(lh * 0.46), int(lw * 0.42));
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

void Connection::press(double x, double y) {
    addon_->touched();
    const int key = keyboard_.keyAt(x, y);
    keyboard_.setPressed(key);
    if (keyboard_.repeats(key)) {
        addon_->type(0xff08);
        startRepeat();
    } else if (keyboard_.isSpace(key)) {
        keyboard_.dragSpace(x);
    }
    draw();
}

void Connection::move(double x, double y) {
    if (keyboard_.isSpace(keyboard_.pressed())) {
        // Sliding along space moves the cursor, as on a phone.
        for (auto sym : keyboard_.dragSpace(x)) {
            addon_->type(sym);
        }
        return;
    }
    const int key = keyboard_.keyAt(x, y);
    if (key == keyboard_.pressed()) {
        return;
    }
    // Sliding to the neighbouring key picks that one instead.
    // Sliding off backspace stops deleting.
    repeat_.reset();
    keyboard_.setPressed(keyboard_.repeats(key) ? -1 : key);
    draw();
}

void Connection::lift() {
    repeat_.reset();
    const auto action = keyboard_.release(keyboard_.pressed());
    if (action.hide) {
        // Unmapping is all it takes, as in plasma-keyboard: KWin drops a
        // panel without a buffer. Telling KWin to deactivate doesn't stick
        // while the text field keeps focus.
        userHide();
        return;
    }
    // Each of these may change what the strip shows; fcitx calls back into
    // update(), which redraws.
    if (action.sym) {
        addon_->type(action.sym);
    }
    if (action.candidate >= 0) {
        addon_->selectCandidate(action.candidate);
    }
    if (action.page) {
        addon_->turnPage(action.page);
    }
    if (action.toggleLanguage) {
        addon_->toggleLanguage();
    }
    if (action.toggleScript) {
        addon_->toggleScript();
    }
    draw();
}

void Connection::cancel() {
    repeat_.reset();
    keyboard_.setPressed(-1);
    keyboard_.release(-1);
    draw();
}

void Connection::startRepeat() {
    auto &loop = addon_->instance()->eventLoop();
    repeat_ = loop.addTimeEvent(
        CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 400000, 0,
        [this](fcitx::EventSourceTime *source, uint64_t) {
            addon_->type(0xff08);
            source->setNextInterval(60000);
            source->setOneShot();
            return true;
        });
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
    // Which language the keys type in, and rime's switches, change with the
    // focused field and the input method.
    for (auto type : {fcitx::EventType::InputContextFocusIn,
                      fcitx::EventType::InputContextSwitchInputMethod,
                      fcitx::EventType::InputContextUpdateUI}) {
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

fcitx::Action *Addon::scriptAction(fcitx::InputContext *ic) {
    // rime names its switches fcitx-rime-<schema>-<option>.
    std::function<fcitx::Action *(const std::vector<fcitx::Action *> &)>
        search = [&](const std::vector<fcitx::Action *> &actions)
        -> fcitx::Action * {
        for (auto *action : actions) {
            const auto &name = action->name();
            if (name.starts_with("fcitx-rime-") &&
                (name.ends_with("-simplification") ||
                 name.ends_with("-traditionalization"))) {
                return action;
            }
            if (auto *menu = action->menu()) {
                if (auto *found = search(menu->actions())) {
                    return found;
                }
            }
        }
        return nullptr;
    };
    return search(ic->statusArea().allActions());
}

void Addon::refresh() {
    State state;
    auto *ic = instance_->lastFocusedInputContext();
    if (ic) {
        const auto *entry = instance_->inputMethodEntry(ic);
        state.chinese = entry && !entry->isKeyboard();
        if (auto *action = state.chinese ? scriptAction(ic) : nullptr) {
            state.scriptLabel = action->shortText(ic);
        }
        // Candidates only while fcitx has handed them to us; in physical
        // keyboard mode they're classicui's.
        if (instance_->inputMethodMode() ==
            fcitx::InputMethodMode::OnScreenKeyboard) {
            auto &panel = ic->inputPanel();
            state.candidates.preedit =
                instance_->outputFilter(ic, panel.preedit()).toString();
            candidateIndex_.clear();
            if (auto list = panel.candidateList()) {
                for (int i = 0; i < list->size(); i++) {
                    const auto &candidate = list->candidate(i);
                    if (candidate.isPlaceHolder()) {
                        continue;
                    }
                    state.candidates.words.push_back(
                        instance_->outputFilter(ic, candidate.text())
                            .toString());
                    candidateIndex_.push_back(i);
                }
                if (auto *pageable = list->toPageable()) {
                    state.candidates.hasPrev = pageable->hasPrev();
                    state.candidates.hasNext = pageable->hasNext();
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
    if (!ic || index < 0 || index >= int(candidateIndex_.size())) {
        return;
    }
    auto list = ic->inputPanel().candidateList();
    const int i = candidateIndex_[index];
    if (list && i < list->size()) {
        list->candidate(i).select(ic);
    }
}

void Addon::turnPage(int direction) {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic) {
        return;
    }
    auto list = ic->inputPanel().candidateList();
    auto *pageable = list ? list->toPageable() : nullptr;
    if (!pageable) {
        return;
    }
    if (direction < 0 && pageable->hasPrev()) {
        pageable->prev();
    } else if (direction > 0 && pageable->hasNext()) {
        pageable->next();
    }
    ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

void Addon::toggleLanguage() {
    // Between the keyboard layout and rime, the way Win+Space does on saren.
    instance_->toggle();
}

void Addon::toggleScript() {
    auto *ic = instance_->lastFocusedInputContext();
    if (!ic) {
        return;
    }
    if (auto *action = scriptAction(ic)) {
        action->activate(ic);
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
