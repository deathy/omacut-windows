QT += core gui quick quickcontrols2 multimedia testlib
CONFIG += c++17 testcase
TARGET = backend_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += \
    ../src/backend.h \
    ../src/ffmpeg.h \
    ../src/filepicker.h \
    ../src/thumbprovider.h \
    ../src/thumbworker.h

SOURCES += \
    backend_tests.cpp \
    ../src/backend.cpp \
    ../src/ffmpeg.cpp \
    ../src/thumbprovider.cpp \
    ../src/thumbworker.cpp

# Match omacut.pro: the picker implementation is platform-bound.
linux {
    QT += dbus
    DEFINES += OMACUT_PORTAL_FILE_PICKER
    HEADERS += ../src/portalfilepicker.h
    SOURCES += ../src/portalfilepicker.cpp
} else {
    QT += widgets
    HEADERS += ../src/dialogfilepicker.h
    SOURCES += ../src/dialogfilepicker.cpp
}
