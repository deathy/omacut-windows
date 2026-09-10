QT += core gui widgets testlib
CONFIG += c++17 testcase
TARGET = dialogfilepicker_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/filepicker.h ../src/dialogfilepicker.h
SOURCES += dialogfilepicker_tests.cpp ../src/dialogfilepicker.cpp
