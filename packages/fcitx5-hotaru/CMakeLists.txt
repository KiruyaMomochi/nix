cmake_minimum_required(VERSION 3.16)
project(fcitx5-hotaru VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(GNUInstallDirs)
find_package(Fcitx5Core 5.1 REQUIRED)
find_package(Fcitx5Module REQUIRED COMPONENTS Wayland DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(Deps REQUIRED IMPORTED_TARGET wayland-client cairo pangocairo)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

set(protocols
    ${WAYLAND_PROTOCOLS_DIR}/unstable/input-method/input-method-unstable-v1.xml
    ${WAYLAND_PROTOCOLS_DIR}/unstable/xdg-output/xdg-output-unstable-v1.xml)
set(protocol_sources)
foreach(xml ${protocols})
    get_filename_component(name ${xml} NAME_WE)
    add_custom_command(
        OUTPUT ${name}-client.h ${name}.c
        COMMAND ${WAYLAND_SCANNER} client-header ${xml} ${name}-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${xml} ${name}.c
        DEPENDS ${xml})
    list(APPEND protocol_sources ${CMAKE_CURRENT_BINARY_DIR}/${name}.c)
endforeach()

add_library(hotaru MODULE src/hotaru.cpp src/keyboard.cpp src/theme.cpp ${protocol_sources})
target_include_directories(hotaru PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(hotaru PRIVATE
    Fcitx5::Core Fcitx5::Module::Wayland Fcitx5::Module::DBus PkgConfig::Deps)
set_target_properties(hotaru PROPERTIES PREFIX "lib")

install(TARGETS hotaru DESTINATION ${CMAKE_INSTALL_LIBDIR}/fcitx5)
install(FILES hotaru.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/fcitx5/addon)
