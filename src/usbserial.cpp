#include "usbserial.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>

// --- helpers ---------------------------------------------------------------

static QString readSys(const QString &dir, const QString &f)
{
    QFile file(dir + QLatin1Char('/') + f);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(file.readAll()).trimmed();
}

QString UsbSerial::findNode(quint16 vid, quint16 pid, QString *err)
{
    QDir base(QStringLiteral("/sys/bus/usb/devices"));
    const QStringList entries =
        base.entryList(QDir::NoDotAndDotDot | QDir::System | QDir::AllEntries, QDir::Name);
    for (const QString &name : entries) {
        if (name.startsWith(QLatin1String("usb")) || name.contains(QLatin1Char(':')))
            continue;
        const QString p = base.absoluteFilePath(name);
        const QString v = readSys(p, QStringLiteral("idVendor"));
        const QString d = readSys(p, QStringLiteral("idProduct"));
        if (v.compare(QString::asprintf("%04x", vid), Qt::CaseInsensitive) == 0 &&
            d.compare(QString::asprintf("%04x", pid), Qt::CaseInsensitive) == 0) {
            const QString bus = readSys(p, QStringLiteral("busnum"));
            const QString dev = readSys(p, QStringLiteral("devnum"));
            if (bus.isEmpty() || dev.isEmpty()) {
                if (err) *err = QStringLiteral("device has no busnum/devnum");
                return QString();
            }
            return QString::asprintf("/dev/bus/usb/%03d/%03d", bus.toInt(), dev.toInt());
        }
    }
    if (err) *err = QStringLiteral("device %1:%2 not attached")
                        .arg(vid, 4, 16, QLatin1Char('0')).arg(pid, 4, 16, QLatin1Char('0'));
    return QString();
}

UsbSerial::~UsbSerial() { close(); }

bool UsbSerial::open(quint16 vid, quint16 pid, QString *err)
{
    close();
    const QString node = findNode(vid, pid, err);
    if (node.isEmpty())
        return false;

    m_fd = ::open(node.toLocal8Bit().constData(), O_RDWR);
    if (m_fd < 0) {
        m_err = QStringLiteral("open %1: %2").arg(node, QString::fromLocal8Bit(strerror(errno)));
        if (err) *err = m_err;
        return false;
    }

    int iface = 0;
    if (ioctl(m_fd, USBDEVFS_CLAIMINTERFACE, &iface) < 0) {
        m_err = QStringLiteral("claim interface: %1").arg(QString::fromLocal8Bit(strerror(errno)));
        if (err) *err = m_err;
        close();
        return false;
    }

    if (!pl2303Init()) {
        if (err) *err = m_err;
        close();
        return false;
    }
    return true;
}

void UsbSerial::close()
{
    if (m_fd >= 0) {
        int iface = 0;
        ioctl(m_fd, USBDEVFS_RELEASEINTERFACE, &iface);
        ::close(m_fd);
        m_fd = -1;
    }
}

bool UsbSerial::ctrl(quint8 requestType, quint8 request, quint16 value, quint16 index,
                     void *data, int len, int timeoutMs)
{
    struct usbdevfs_ctrltransfer ct;
    memset(&ct, 0, sizeof(ct));
    ct.bRequestType = requestType;
    ct.bRequest = request;
    ct.wValue = value;
    ct.wIndex = index;
    ct.wLength = len;
    ct.timeout = timeoutMs;
    ct.data = data;
    const int r = ioctl(m_fd, USBDEVFS_CONTROL, &ct);
    if (r < 0) {
        m_err = QStringLiteral("control(%1): %2")
                    .arg(request).arg(QString::fromLocal8Bit(strerror(errno)));
        return false;
    }
    return true;
}

bool UsbSerial::vendorRead(quint16 value, quint8 *out)
{
    quint8 buf = 0;
    if (!ctrl(0xC0, 0x01, value, 0, &buf, 1, 100))
        return false;
    if (out) *out = buf;
    return true;
}

bool UsbSerial::vendorWrite(quint16 value, quint16 index)
{
    return ctrl(0x40, 0x01, value, index, nullptr, 0, 100);
}

// PL2303 magic init (from the Linux pl2303 driver, HX/older path). Works for
// the common HX-class and many clones; if a device needs the HXN path we can
// branch on bcdDevice later.
bool UsbSerial::pl2303Init()
{
    quint8 b;
    bool ok = true;
    ok &= vendorRead(0x8484, &b);
    ok &= vendorWrite(0x0404, 0);
    ok &= vendorRead(0x8484, &b);
    ok &= vendorRead(0x8383, &b);
    ok &= vendorRead(0x8484, &b);
    ok &= vendorWrite(0x0404, 1);
    ok &= vendorRead(0x8484, &b);
    ok &= vendorRead(0x8383, &b);
    ok &= vendorWrite(0, 1);
    ok &= vendorWrite(1, 0);
    ok &= vendorWrite(2, 0x44);
    if (!ok)
        m_err = QStringLiteral("PL2303 init failed: %1").arg(m_err);
    return ok;
}

bool UsbSerial::setLineCoding(int baud)
{
    // CDC SET_LINE_CODING: dwDTERate (LE32), bCharFormat(0=1 stop),
    // bParityType(0=none), bDataBits(8).
    quint8 lc[7];
    lc[0] = baud & 0xFF;
    lc[1] = (baud >> 8) & 0xFF;
    lc[2] = (baud >> 16) & 0xFF;
    lc[3] = (baud >> 24) & 0xFF;
    lc[4] = 0;   // 1 stop bit
    lc[5] = 0;   // no parity
    lc[6] = 8;   // 8 data bits
    if (!ctrl(0x21, 0x20, 0, 0, lc, sizeof(lc), 100))
        return false;
    // Assert DTR + RTS (SET_CONTROL_LINE_STATE).
    return ctrl(0x21, 0x22, 0x03, 0, nullptr, 0, 100);
}

bool UsbSerial::writeBulk(const QByteArray &data, int timeoutMs)
{
    struct usbdevfs_bulktransfer bt;
    memset(&bt, 0, sizeof(bt));
    bt.ep = m_epOut;
    bt.len = data.size();
    bt.timeout = timeoutMs;
    bt.data = const_cast<char *>(data.constData());
    const int r = ioctl(m_fd, USBDEVFS_BULK, &bt);
    if (r < 0) {
        m_err = QStringLiteral("bulk write: %1").arg(QString::fromLocal8Bit(strerror(errno)));
        return false;
    }
    return true;
}

QByteArray UsbSerial::readBulk(int maxLen, int timeoutMs)
{
    QByteArray buf(maxLen, Qt::Uninitialized);
    struct usbdevfs_bulktransfer bt;
    memset(&bt, 0, sizeof(bt));
    bt.ep = m_epIn;
    bt.len = maxLen;
    bt.timeout = timeoutMs;
    bt.data = buf.data();
    const int r = ioctl(m_fd, USBDEVFS_BULK, &bt);
    if (r < 0) {
        if (errno != ETIMEDOUT)
            m_err = QStringLiteral("bulk read: %1").arg(QString::fromLocal8Bit(strerror(errno)));
        return QByteArray();
    }
    buf.resize(r);
    return buf;
}
