# Neutral packaging metadata — no personal identifiers.
%define _buildhost reproducible-builder

Name:       harbour-svero
Summary:    Read & chart Veroval blood-pressure measurements over USB
Version:    0.1.0
Release:    1
License:    GPL-3.0-or-later
URL:        https://github.com/JimKnopfIoT/harbour-svero
Source0:    %{name}-%{version}.tar.bz2
Vendor:     harbour-svero contributors
Packager:   harbour-svero contributors

Requires:   sailfishsilica-qt5
BuildRequires: pkgconfig(sailfishapp)
BuildRequires: pkgconfig(Qt5Core)
BuildRequires: pkgconfig(Qt5Qml)
BuildRequires: pkgconfig(Qt5Quick)
BuildRequires: desktop-file-utils

%description
Native SailfishOS app that downloads stored measurements from a Veroval
blood-pressure monitor (Prolific PL2303 USB serial, spoken directly via
usbdevfs — no libusb or kernel driver needed), charts systolic/diastolic/pulse
over time, and exports CSV and an image.

%prep
%setup -q

%build
%qmake5
%make_build

%install
%qmake5_install

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
%config %{_sysconfdir}/udev/rules.d/999-veroval.rules

%changelog
* Thu Jul 30 2026 harbour-svero contributors 0.1.0-1
- Initial: PL2303 usbdevfs transport, BPM record download + parse, CSV export.
