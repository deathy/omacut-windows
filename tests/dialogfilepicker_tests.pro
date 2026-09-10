QT += core gui widgets testlib
CONFIG += c++17 testcase
# qmake builds a GUI-subsystem binary on Windows by default, which detaches
# stdout -- QtTest's results would go nowhere.
win32: CONFIG += console
TARGET = dialogfilepicker_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/filepicker.h ../src/dialogfilepicker.h
SOURCES += dialogfilepicker_tests.cpp ../src/dialogfilepicker.cpp
