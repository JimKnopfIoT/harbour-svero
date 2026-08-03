#include "veroval.h"
#include "usbserial.h"

#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QVariantMap>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSet>
#include <algorithm>

static const quint16 kVid = 0x067b;
static const quint16 kPid = 0x2303;

// The two binary requests from the reverse-engineered BPM protocol.
static const QByteArray kReqData  = QByteArray::fromHex("A5F90101FB");
static const QByteArray kReqClose = QByteArray::fromHex("A6F90101FB");

// --- worker ----------------------------------------------------------------

void VeroWorker::run()
{
    UsbSerial usb;
    QString err;
    emit progress(QStringLiteral("Opening device…"));
    if (!usb.open(m_vid, m_pid, &err)) {
        emit failed(err);
        return;
    }
    if (!usb.setLineCoding(m_baud)) {
        emit failed(usb.lastError());
        return;
    }

    // Drain a reply block until the device goes idle (read timeout) or a cap.
    // A5 dumps person 1, A6 dumps person 2 — cpresser only ever read A5, which
    // is why it saw a single memory bank.
    QByteArray blockA, blockB;

    emit progress(QStringLiteral("Reading person 1…"));
    if (usb.writeBulk(kReqData)) {
        for (int i = 0; i < 512 && blockA.size() < 16384; ++i) {
            const QByteArray chunk = usb.readBulk(64, 1000);
            if (chunk.isEmpty()) break;
            blockA.append(chunk);
        }
    }

    emit progress(QStringLiteral("Reading person 2…"));
    if (usb.writeBulk(kReqClose)) {
        for (int i = 0; i < 512 && blockB.size() < 16384; ++i) {
            const QByteArray chunk = usb.readBulk(64, 1000);
            if (chunk.isEmpty()) break;
            blockB.append(chunk);
        }
    }

    usb.close();

    if (blockA.isEmpty() && blockB.isEmpty())
        emit failed(QStringLiteral("No data received (check the device is in PC/transfer mode)."));
    else
        emit finished(blockA, blockB);
}

// --- facade ----------------------------------------------------------------

Veroval::Veroval(QObject *parent) : QObject(parent)
{
    m_status = tr("Not connected");
    loadSettings();
    loadData();
}

void Veroval::setStatus(const QString &s)
{
    if (m_status != s) { m_status = s; emit statusTextChanged(); }
}

void Veroval::setBaud(int b)
{
    if (m_baud != b) { m_baud = b; emit baudChanged(); }
}

void Veroval::setChartPerson(int person)
{
    const int p = (person == 2) ? 2 : 1;
    if (m_chartPerson == p)
        return;
    m_chartPerson = p;
    saveSettings();
    emit chartPersonChanged();
}

int Veroval::personOf(const QVariantMap &m)
{
    const QVariant override = m.value(QStringLiteral("person"));
    const int p = override.isValid() ? override.toInt()
                                     : m.value(QStringLiteral("user")).toInt();
    return (p == 2) ? 2 : 1;
}

void Veroval::assignPerson(int index, int person)
{
    if (index < 0 || index >= m_measurements.size())
        return;
    QVariantMap m = m_measurements.at(index).toMap();
    const int p = (person == 2) ? 2 : 1;
    if (personOf(m) == p)
        return;
    m.insert(QStringLiteral("person"), p);
    m_measurements[index] = m;
    saveData();
    // Deliberately not measurementsChanged: see personRevision in the header.
    ++m_personRevision;
    emit personRevisionChanged();
}

void Veroval::download()
{
    if (m_busy)
        return;
    m_busy = true;
    emit busyChanged();
    setStatus(tr("Connecting…"));

    m_worker = new VeroWorker(kVid, kPid, m_baud, this);
    connect(m_worker, &VeroWorker::progress, this, &Veroval::onWorkerProgress);
    connect(m_worker, &VeroWorker::finished, this, &Veroval::onWorkerFinished);
    connect(m_worker, &VeroWorker::failed, this, &Veroval::onWorkerFailed);
    connect(m_worker, &QThread::finished, m_worker, &QObject::deleteLater);
    m_worker->start();
}

void Veroval::onWorkerProgress(const QString &msg)
{
    setStatus(msg);
}

void Veroval::onWorkerFinished(const QByteArray &blockA, const QByteArray &blockB)
{
    m_busy = false;
    emit busyChanged();

    m_blocks.clear();
    m_blocks.append(blockA);
    m_blocks.append(blockB);
    rebuildRawHex();

    // Merge the new readings into the archive (dedup by user+timestamp) so the
    // archive accumulates past the device's 99-record limit over time.
    const int added = mergeRecords(parseBlocks(3, 14));
    saveData();
    setStatus(tr("Downloaded: %1 new, %2 total").arg(added).arg(m_measurements.size()));
}

void Veroval::rebuildRawHex()
{
    QString hex;
    for (int bi = 0; bi < m_blocks.size(); ++bi) {
        const QByteArray &blk = m_blocks.at(bi);
        if (blk.isEmpty()) continue;
        hex += QStringLiteral("--- %1 (%2 bytes) ---\n")
                   .arg(bi == 0 ? QStringLiteral("A5 / Person 1") : QStringLiteral("A6 / Person 2"))
                   .arg(blk.size());
        for (int i = 0; i < blk.size(); ++i) {
            if (i) hex += QLatin1Char(' ');
            hex += QString::asprintf("%02X", quint8(blk.at(i)));
        }
        hex += QLatin1Char('\n');
    }
    m_rawHex = hex;
    emit rawHexChanged();
}

QString Veroval::dataFile() const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath();
    return dir + QStringLiteral("/last-download.json");
}

QString Veroval::settingsFile() const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath();
    return dir + QStringLiteral("/settings.json");
}

void Veroval::saveSettings() const
{
    QDir().mkpath(QFileInfo(settingsFile()).absolutePath());
    QJsonObject obj;
    obj.insert(QStringLiteral("chartPerson"), m_chartPerson);
    QFile f(settingsFile());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void Veroval::loadSettings()
{
    QFile f(settingsFile());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
    const int p = obj.value(QStringLiteral("chartPerson")).toInt(1);
    m_chartPerson = (p == 2) ? 2 : 1;
}

static QJsonObject archiveToJson(const QVariantList &measurements)
{
    QJsonArray arr;
    for (const QVariant &v : measurements)
        arr.append(QJsonObject::fromVariantMap(v.toMap()));
    QJsonObject obj;
    obj.insert(QStringLiteral("app"), QStringLiteral("harbour-svero"));
    obj.insert(QStringLiteral("measurements"), arr);
    obj.insert(QStringLiteral("savedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    return obj;
}

void Veroval::saveData() const
{
    QDir().mkpath(QFileInfo(dataFile()).absolutePath());
    QFile f(dataFile());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(archiveToJson(m_measurements)).toJson(QJsonDocument::Compact));
}

void Veroval::loadData()
{
    QFile f(dataFile());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonArray arr = QJsonDocument::fromJson(f.readAll())
                               .object().value(QStringLiteral("measurements")).toArray();
    m_measurements.clear();
    for (const QJsonValue &v : arr) {
        QVariantMap m = v.toObject().toVariantMap();
        // Archives written before the P1/P2 override existed carry no `person`;
        // seed it from the device's memory slot so the chart can filter on it.
        if (!m.contains(QStringLiteral("person")))
            m.insert(QStringLiteral("person"), personOf(m));
        m_measurements.append(m);
    }
    // keep newest-first ordering
    std::sort(m_measurements.begin(), m_measurements.end(),
              [](const QVariant &a, const QVariant &b) {
                  return a.toMap().value(QStringLiteral("epoch")).toLongLong()
                       > b.toMap().value(QStringLiteral("epoch")).toLongLong();
              });
    emit measurementsChanged();
    if (!m_measurements.isEmpty())
        setStatus(tr("Loaded %1 saved measurement(s)").arg(m_measurements.size()));
}

QString Veroval::saveToFile()
{
    if (m_measurements.isEmpty()) {
        emit actionError(tr("Nothing to save."));
        return QString();
    }
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (dir.isEmpty())
        dir = QDir::homePath();
    QDir().mkpath(dir);
    const QString path = dir + QStringLiteral("/veroval-archive-")
                       + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))
                       + QStringLiteral(".json");
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit actionError(tr("Cannot write %1").arg(path));
        return QString();
    }
    f.write(QJsonDocument(archiveToJson(m_measurements)).toJson(QJsonDocument::Indented));
    emit actionInfo(tr("Saved %1 readings: %2").arg(m_measurements.size()).arg(path));
    return path;
}

void Veroval::loadFromFile(const QString &path, bool merge)
{
    QString p = path;
    if (p.startsWith(QStringLiteral("file://")))
        p = p.mid(7);
    QFile f(p);
    if (!f.open(QIODevice::ReadOnly)) {
        emit actionError(tr("Cannot open %1").arg(p));
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    QJsonArray arr = doc.object().value(QStringLiteral("measurements")).toArray();
    if (arr.isEmpty() && doc.isArray())
        arr = doc.array();              // tolerate a bare array
    if (arr.isEmpty()) {
        emit actionError(tr("No measurements in that file."));
        return;
    }
    QVariantList recs;
    for (const QJsonValue &v : arr)
        recs.append(v.toObject().toVariantMap());
    if (!merge)
        m_measurements.clear();
    const int added = mergeRecords(recs);
    saveData();
    emit actionInfo(tr("Loaded %1: +%2 (%3 total)")
                        .arg(QFileInfo(p).fileName()).arg(added).arg(m_measurements.size()));
}

void Veroval::clearArchive()
{
    m_measurements.clear();
    saveData();
    emit measurementsChanged();
    setStatus(tr("Archive cleared"));
}

void Veroval::onWorkerFailed(const QString &err)
{
    m_busy = false;
    emit busyChanged();
    setStatus(tr("Failed: %1").arg(err));
    emit actionError(err);
}

void Veroval::reparse(int base, int recordLen)
{
    if (m_blocks.isEmpty()) {
        emit actionError(tr("Nothing captured yet."));
        return;
    }
    const int added = mergeRecords(parseBlocks(base, recordLen));
    emit actionInfo(tr("Re-parsed: +%1 (%2 total)").arg(added).arg(m_measurements.size()));
}

QString Veroval::keyFor(const QVariantMap &m)
{
    return m.value(QStringLiteral("user")).toString() + QLatin1Char(':')
         + QString::number(m.value(QStringLiteral("epoch")).toLongLong());
}

int Veroval::mergeRecords(const QVariantList &recs)
{
    QSet<QString> keys;
    for (const QVariant &v : m_measurements)
        keys.insert(keyFor(v.toMap()));
    int added = 0;
    for (const QVariant &v : recs) {
        QVariantMap m = v.toMap();
        const QString k = keyFor(m);
        if (keys.contains(k)) continue;      // keeps the existing record, and
        keys.insert(k);                      // with it any person assignment
        if (!m.contains(QStringLiteral("person")))
            m.insert(QStringLiteral("person"), personOf(m));
        m_measurements.append(m);
        ++added;
    }
    std::sort(m_measurements.begin(), m_measurements.end(),
              [](const QVariant &a, const QVariant &b) {
                  return a.toMap().value(QStringLiteral("epoch")).toLongLong()
                       > b.toMap().value(QStringLiteral("epoch")).toLongLong();
              });
    emit measurementsChanged();
    return added;
}

QVariantList Veroval::parseBlocks(int base, int recordLen) const
{
    QVariantList out;
    for (const QByteArray &blk : m_blocks)
        if (!blk.isEmpty())
            parseBlock(out, blk, base, recordLen);
    return out;
}

// Parse fixed-width records from one response block. Default layout (BPM25,
// cpresser):
//   [0]user [1]index [2]pad [3]systolic [4]pad [5]diastolic [6]flags [7]pulse
//   [8]month [9]day [10..11]year(BE) [12]hour [13]minute
void Veroval::parseBlock(QVariantList &out, const QByteArray &raw, int base, int recordLen) const
{
    const auto u8 = [&raw](int i) -> int {
        return (i >= 0 && i < raw.size()) ? quint8(raw.at(i)) : -1;
    };

    for (int off = base; off + recordLen <= raw.size(); off += recordLen) {
        const int sys = u8(off + 3);
        const int dia = u8(off + 5);
        const int pulse = u8(off + 7);
        const int month = u8(off + 8);
        const int day = u8(off + 9);
        const int year = u8(off + 10) * 256 + u8(off + 11);
        const int hour = u8(off + 12);
        const int minute = u8(off + 13);

        // Plausibility gate: only accept physiologically sane readings with a
        // valid timestamp. This rejects padding and any junk the A6/person-2
        // block may contain, so it can't pollute the averages.
        const bool bpOk = sys >= 60 && sys <= 260 && dia >= 30 && dia <= 200
                        && sys > dia && pulse >= 30 && pulse <= 220;
        const bool dateOk = year >= 2000 && year <= 2100
                        && month >= 1 && month <= 12 && day >= 1 && day <= 31
                        && hour <= 23 && minute <= 59;
        if (!bpOk || !dateOk)
            continue;

        QVariantMap m;
        m.insert(QStringLiteral("user"), u8(off + 0));
        m.insert(QStringLiteral("index"), u8(off + 1));
        m.insert(QStringLiteral("systolic"), sys);
        m.insert(QStringLiteral("diastolic"), dia);
        m.insert(QStringLiteral("pulse"), pulse);
        m.insert(QStringLiteral("arrhythmia"), (u8(off + 6) != 0));

        QDateTime dt(QDate(year, qBound(1, month, 12), qBound(1, day, 31)),
                     QTime(qBound(0, hour, 23), qBound(0, minute, 59)));
        m.insert(QStringLiteral("timestamp"), dt.isValid() ? dt.toString(QStringLiteral("yyyy-MM-dd HH:mm")) : QStringLiteral("?"));
        m.insert(QStringLiteral("epoch"), dt.isValid() ? dt.toMSecsSinceEpoch() / 1000 : 0);
        out.append(m);
    }
}

QString Veroval::exportCsv()
{
    if (m_measurements.isEmpty()) {
        emit actionError(tr("No measurements to export."));
        return QString();
    }
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (dir.isEmpty())
        dir = QDir::homePath();
    QDir().mkpath(dir);
    const QString path = dir + QStringLiteral("/veroval-")
                       + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))
                       + QStringLiteral(".csv");

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit actionError(tr("Cannot write %1").arg(path));
        return QString();
    }
    f.write("timestamp,person,user,systolic,diastolic,pulse,arrhythmia\n");
    for (const QVariant &v : m_measurements) {
        const QVariantMap m = v.toMap();
        const QString line = QStringLiteral("%1,%2,%3,%4,%5,%6,%7\n")
            .arg(m.value(QStringLiteral("timestamp")).toString())
            .arg(personOf(m))
            .arg(m.value(QStringLiteral("user")).toInt())
            .arg(m.value(QStringLiteral("systolic")).toInt())
            .arg(m.value(QStringLiteral("diastolic")).toInt())
            .arg(m.value(QStringLiteral("pulse")).toInt())
            .arg(m.value(QStringLiteral("arrhythmia")).toBool() ? 1 : 0);
        f.write(line.toUtf8());
    }
    f.close();
    emit actionInfo(tr("CSV exported: %1").arg(path));
    return path;
}

QString Veroval::reserveImagePath()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (dir.isEmpty())
        dir = QDir::homePath();
    QDir().mkpath(dir);
    return dir + QStringLiteral("/veroval-chart-")
         + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))
         + QStringLiteral(".jpg");
}
