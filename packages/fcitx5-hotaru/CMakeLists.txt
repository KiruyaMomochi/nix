cmake_minimum_required(VERSION 3.16)
project(fcitx5-hotaru VERSION 0.2.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(GNUInstallDirs)
find_package(Fcitx5Core 5.1 REQUIRED)
find_package(Fcitx5Module REQUIRED COMPONENTS Wayland)
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

# fcitx's Wayland wrappers are not installed; classicui builds them from the
# fcitx5 source tree too. Must be the same fcitx5 version that loads us.
set(FCITX5_SOURCE "" CACHE PATH "fcitx5 source tree")
set(fcitx_wayland ${FCITX5_SOURCE}/src/lib/fcitx-wayland/core)
set(fcitx_wayland_sources
    ${fcitx_wayland}/wl_surface.cpp ${fcitx_wayland}/wl_callback.cpp
    ${fcitx_wayland}/wl_buffer.cpp ${fcitx_wayland}/wl_region.cpp
    ${fcitx_wayland}/wl_output.cpp)

add_library(hotaru MODULE src/hotaru.cpp src/keyboard.cpp src/theme.cpp
    ${protocol_sources} ${fcitx_wayland_sources})
target_include_directories(hotaru PRIVATE ${CMAKE_CURRENT_BINARY_DIR} ${fcitx_wayland})
target_link_options(hotaru PRIVATE -Wl,--no-undefined)
target_compile_definitions(hotaru PRIVATE
    HOTARU_DATADIR="${CMAKE_INSTALL_FULL_DATADIR}/fcitx5/hotaru")
target_link_libraries(hotaru PRIVATE
    Fcitx5::Core Fcitx5::Module::Wayland PkgConfig::Deps)
set_target_properties(hotaru PROPERTIES PREFIX "lib")

install(TARGETS hotaru DESTINATION ${CMAKE_INSTALL_LIBDIR}/fcitx5)
install(FILES hotaru.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/fcitx5/addon)
install(FILES data/kaomoji.txt DESTINATION ${CMAKE_INSTALL_DATADIR}/fcitx5/hotaru)
