# Upstream's backend test project, adjusted from outside the same way
# omacut-windows.pro adjusts omacut.pro. See PORT.md, "File picker".

include(backend_tests.pro)

!contains(SOURCES, ../src/portalfilepicker.cpp) {
    error("backend_tests.pro no longer lists ../src/portalfilepicker.cpp -- upstream reworked the file picker; see PORT.md")
}
QT      -= dbus
HEADERS -= ../src/portalfilepicker.h
SOURCES -= ../src/portalfilepicker.cpp

QT      += widgets
HEADERS += ../src/dialogfilepicker.h
SOURCES += ../src/dialogfilepicker.cpp

# Leaves out the tests of the portal picker, which this build doesn't have.
DEFINES += OMACUT_NO_PORTAL_PICKER

# qmake builds a GUI-subsystem binary on Windows by default, which detaches
# stdout -- QtTest's results would go nowhere.
win32: CONFIG += console
# and an .app bundle on macOS, which nothing would look inside for.
macx: CONFIG -= app_bundle
