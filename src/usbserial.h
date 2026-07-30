#ifndef USBSERIAL_H
#define USBSERIAL_H

#include <QString>
#include <QByteArray>

// Minimal userspace USB-serial for a Prolific PL2303, via the raw kernel
// usbdevfs interface (/dev/bus/usb/<bus>/<dev>). No libusb and no in-kernel
// pl2303 driver are required (neither exists on this device). Synchronous —
// intended to be driven from a worker thread.
class UsbSerial
{
public:
    UsbSerial() = default;
    ~UsbSerial();

    // Find the device by VID/PID in sysfs, open its usbdevfs node, claim the
    // interface and run the PL2303 init. Returns false + sets *err on failure.
    bool open(quint16 vid, quint16 pid, QString *err);
    void close();
    bool isOpen() const { return m_fd >= 0; }

    // Configure the UART: baud, 8 data bits, no parity, 1 stop bit, DTR+RTS on.
    bool setLineCoding(int baud);

    bool writeBulk(const QByteArray &data, int timeoutMs = 1000);
    // Read up to maxLen bytes; returns what arrived (empty on timeout).
    QByteArray readBulk(int maxLen, int timeoutMs);

    QString lastError() const { return m_err; }

private:
    bool ctrl(quint8 requestType, quint8 request, quint16 value, quint16 index,
              void *data, int len, int timeoutMs);
    bool vendorRead(quint16 value, quint8 *out);
    bool vendorWrite(quint16 value, quint16 index);
    bool pl2303Init();
    static QString findNode(quint16 vid, quint16 pid, QString *err);

    int m_fd = -1;
    int m_epIn = 0x83;    // bulk IN
    int m_epOut = 0x02;   // bulk OUT
    QString m_err;
};

#endif // USBSERIAL_H
