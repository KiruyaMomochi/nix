#include "theme.h"

#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>

namespace hotaru {
namespace {

using Ini = std::map<std::string, std::map<std::string, std::string>>;

Ini readIni(const std::string &path) {
    Ini ini;
    std::ifstream in(path);
    std::string line, group;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }
        if (line.front() == '[' && line.back() == ']') {
            group = line.substr(1, line.size() - 2);
            continue;
        }
        auto eq = line.find('=');
        if (eq != std::string::npos) {
            ini[group][line.substr(0, eq)] = line.substr(eq + 1);
        }
    }
    return ini;
}

void readColor(const Ini &ini, const char *group, const char *key,
               Color &out) {
    auto g = ini.find(group);
    if (g == ini.end()) {
        return;
    }
    auto k = g->second.find(key);
    if (k == g->second.end()) {
        return;
    }
    int r, gr, b;
    char c1, c2;
    std::istringstream s(k->second);
    if (s >> r >> c1 >> gr >> c2 >> b) {
        out = {r / 255.0, gr / 255.0, b / 255.0};
    }
}

} // namespace

Theme Theme::load() {
    std::string dir;
    if (const char *xdg = std::getenv("XDG_CONFIG_HOME"); xdg && *xdg) {
        dir = xdg;
    } else if (const char *home = std::getenv("HOME")) {
        dir = std::string(home) + "/.config";
    }
    Theme theme;
    auto ini = readIni(dir + "/kdeglobals");
    readColor(ini, "Colors:Window", "BackgroundNormal", theme.background);
    readColor(ini, "Colors:Button", "BackgroundNormal", theme.key);
    readColor(ini, "Colors:Window", "BackgroundAlternate", theme.keyAlt);
    readColor(ini, "Colors:Button", "ForegroundNormal", theme.text);
    readColor(ini, "Colors:Selection", "BackgroundNormal", theme.accent);
    readColor(ini, "General", "AccentColor", theme.accent);
    if (auto g = ini.find("General"); g != ini.end()) {
        if (auto f = g->second.find("font"); f != g->second.end()) {
            theme.font = f->second.substr(0, f->second.find(','));
        }
    }
    return theme;
}

} // namespace hotaru
