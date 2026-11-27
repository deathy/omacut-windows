# What the port changes in upstream's build, applied from outside so that
# upstream's CMakeLists.txt never needs patching. See PORT.md, "File picker"
# and "Windows executable metadata".
#
# The build passes this file as CMAKE_PROJECT_INCLUDE, so CMake runs it right
# after upstream's project() call, before any target exists. It finds what the
# port needs on top of upstream's packages, then defers the actual adjustments
# to the end of upstream's CMakeLists.txt, when its targets are all defined:
#
#   cmake -S work -B build -DCMAKE_PROJECT_INCLUDE=work/port/omacut-port.cmake

# QFileDialog is a widget.
find_package(Qt6 REQUIRED COMPONENTS Widgets)

# Drops every entry of a target's list property that matches a regex.
function(omacut_port_filter target property regex)
    get_target_property(values ${target} ${property})
    if(NOT values)
        return()
    endif()
    list(FILTER values EXCLUDE REGEX "${regex}")
    set_property(TARGET ${target} PROPERTY ${property} "${values}")
endfunction()

function(omacut_port_adjust)
    foreach(target omacut_core omacut omacut_tests)
        if(NOT TARGET ${target})
            message(FATAL_ERROR "Upstream's CMakeLists.txt no longer defines ${target} -- "
                                "its build was reworked; see PORT.md")
        endif()
    endforeach()

    # Swap the xdg-desktop-portal picker (D-Bus, Linux only) for the
    # QFileDialog one. Upstream globs src/, so the overlay's
    # dialogfilepicker.* are in already, and so is the portal picker. Check
    # it is there before removing it: if it was renamed, the filter would
    # quietly do nothing and the build would fail somewhere less obvious.
    get_target_property(core_sources omacut_core SOURCES)
    list(FILTER core_sources INCLUDE REGEX "/src/portalfilepicker\\.cpp$")
    if(NOT core_sources)
        message(FATAL_ERROR "omacut_core no longer builds src/portalfilepicker.cpp -- "
                            "upstream reworked the file picker; see PORT.md")
    endif()
    omacut_port_filter(omacut_core SOURCES "/src/portalfilepicker\\.(cpp|h)$")
    get_target_property(core_sources omacut_core SOURCES)
    list(FILTER core_sources INCLUDE REGEX "/src/dialogfilepicker\\.cpp$")
    if(NOT core_sources)
        target_sources(omacut_core PRIVATE
            ${CMAKE_SOURCE_DIR}/src/dialogfilepicker.cpp
            ${CMAKE_SOURCE_DIR}/src/dialogfilepicker.h)
    endif()

    # Qt6::DBus goes, Qt6::Widgets comes in. omacut_core links publicly, so
    # both the link and the interface lists hold it.
    foreach(property LINK_LIBRARIES INTERFACE_LINK_LIBRARIES)
        omacut_port_filter(omacut_core ${property} "^Qt6?::DBus$")
    endforeach()
    target_link_libraries(omacut_core PUBLIC Qt6::Widgets)

    # Leaves out the tests of the portal picker, which this build doesn't have.
    target_compile_definitions(omacut_tests PRIVATE OMACUT_NO_PORTAL_PICKER)

    # The tests of the picker that replaces it.
    add_executable(dialogfilepicker_tests ${CMAKE_SOURCE_DIR}/tests/dialogfilepicker_tests.cpp)
    target_link_libraries(dialogfilepicker_tests PRIVATE omacut_core Qt6::Test)
    add_test(NAME dialogfilepicker_tests COMMAND dialogfilepicker_tests)
    set_tests_properties(dialogfilepicker_tests PROPERTIES ENVIRONMENT QT_QPA_PLATFORM=offscreen)

    if(MSVC)
        # Upstream's warning flags are GCC's. MSVC reads -Wall as /Wall, which
        # buries the build in warnings from Qt's own headers, and rejects the
        # rest. Keep MSVC's usual level instead.
        foreach(target omacut_core omacut omacut_tests)
            foreach(property COMPILE_OPTIONS INTERFACE_COMPILE_OPTIONS)
                omacut_port_filter(${target} ${property} "^-W")
            endforeach()
        endforeach()
        # The sources are UTF-8, as on Linux.
        target_compile_options(omacut_core PUBLIC /W3 /utf-8)
    endif()

    if(WIN32)
        # A GUI-subsystem executable, or Windows opens a console beside it.
        set_target_properties(omacut PROPERTIES WIN32_EXECUTABLE TRUE)

        # The icon and version-info strings Explorer shows for omacut.exe.
        set(icon "${CMAKE_SOURCE_DIR}/pkgbuild/omacut.ico")
        file(TO_NATIVE_PATH "${icon}" icon)
        string(REPLACE "\\" "\\\\" icon "${icon}")
        file(CONFIGURE OUTPUT "${CMAKE_BINARY_DIR}/omacut.rc" @ONLY CONTENT [[
#include <winver.h>
IDI_ICON1 ICON "@icon@"
VS_VERSION_INFO VERSIONINFO
FILEOS VOS_NT_WINDOWS32
FILETYPE VFT_APP
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904b0"
        BEGIN
            VALUE "FileDescription", "Dead-simple video length trimmer\0"
            VALUE "LegalCopyright", "MIT\0"
            VALUE "OriginalFilename", "omacut.exe\0"
            VALUE "ProductName", "omacut\0"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x0409, 1200
    END
END
]])
        target_sources(omacut PRIVATE "${CMAKE_BINARY_DIR}/omacut.rc")
    endif()
endfunction()

cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL omacut_port_adjust)
