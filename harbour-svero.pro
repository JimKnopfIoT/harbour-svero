# harbour-svero — native SailfishOS app to read Veroval BP measurements over USB
# (Prolific PL2303, raw usbdevfs — no libusb / kernel serial driver needed),
# chart them, and export CSV / image.

TARGET = harbour-svero

CONFIG += sailfishapp sailfishapp_i18n c++17
QT += quick gui

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

INCLUDEPATH += src

HEADERS += \
    src/usbserial.h \
    src/veroval.h

SOURCES += \
    src/harbour-svero.cpp \
    src/usbserial.cpp \
    src/veroval.cpp

# Runs unsandboxed (no [X-Sailjail] in the .desktop) so it can reach the raw
# USB device node /dev/bus/usb/*.
udevrule.files = data/999-veroval.rules
udevrule.path  = /etc/udev/rules.d
INSTALLS += udevrule
# NB: name must sort AFTER 999-android-system.rules (which forces MODE 0660 on
# USB nodes) so our MODE 0666 wins — hence "999-veroval", not "99-".

DISTFILES += \
    qml/harbour-svero.qml \
    qml/pages/MainPage.qml \
    qml/pages/ChartPage.qml \
    qml/pages/RawPage.qml \
    qml/cover/CoverPage.qml \
    harbour-svero.desktop \
    rpm/harbour-svero.spec
