# The project file the Windows build uses. It takes upstream's omacut.pro as it
# is and adjusts it from outside, so upstream's file never needs patching.
# See PORT.md, "File picker", "Windows executable metadata" and "macOS".

include(omacut.pro)

# Swap the xdg-desktop-portal picker (D-Bus, Linux only) for the QFileDialog
# one. Check upstream still lists the portal sources first: if they were
# renamed, the -= lines below would quietly do nothing and the build would
# fail somewhere far less obvious.
!contains(SOURCES, src/portalfilepicker.cpp) {
    error("omacut.pro no longer lists src/portalfilepicker.cpp -- upstream reworked the file picker; see PORT.md")
}
QT      -= dbus
HEADERS -= src/portalfilepicker.h
SOURCES -= src/portalfilepicker.cpp

# QFileDialog is a widget.
QT      += widgets
HEADERS += src/dialogfilepicker.h
SOURCES += src/dialogfilepicker.cpp

win32 {
    RC_ICONS = $$PWD/pkgbuild/omacut.ico
    QMAKE_TARGET_PRODUCT = omacut
    QMAKE_TARGET_DESCRIPTION = Dead-simple video length trimmer
    QMAKE_TARGET_COPYRIGHT = MIT
}

# The experimental macOS build. qmake makes omacut.app on its own; this gives
# it an icon and an identifier that isn't qmake's com.yourcompany placeholder.
macx {
    ICON = $$PWD/pkgbuild/omacut.icns
    QMAKE_TARGET_BUNDLE_PREFIX = io.github.deathy
}
