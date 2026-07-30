# Attribution

## Protocol

The Veroval BPM record protocol (19200 baud; requests `A5 F9 01 01 FB` for
person 1 and `A6 F9 01 01 FB` for person 2; 14-byte records) was reconstructed
from community reverse-engineering work:

* [cpresser/veroval](https://github.com/cpresser/veroval) — Veroval BPM25
  (binary protocol over PL2303). The record layout used here matches this work.
* [ignisf/vdc_export](https://github.com/ignisf/vdc_export) — Veroval *duo
  control* (CDC-ACM, ASCII protocol). Referenced for comparison; that model is
  not supported by this app.

No source code from those projects was copied.

## PL2303

The USB-serial init sequence follows the public behaviour of the Linux kernel
`pl2303` driver (vendor read/write control requests + CDC `SET_LINE_CODING`),
reimplemented here against the raw `usbdevfs` ioctl interface.

## Icon

Original artwork (a heart with a lightning-bolt cut-out), created for this
project.
