#ifndef VEROVAL_H
#define VEROVAL_H

#include <QObject>
#include <QThread>
#include <QVariantList>
#include <QByteArray>

// Runs the blocking USB download off the UI thread.
class VeroWorker : public QThread
{
    Q_OBJECT
public:
    VeroWorker(quint16 vid, quint16 pid, int baud, QObject *parent = nullptr)
        : QThread(parent), m_vid(vid), m_pid(pid), m_baud(baud) {}
    void run() override;
signals:
    void progress(const QString &msg);
    // Two response blocks: A5 (person 1) and A6 (person 2). Either may be empty.
    void finished(const QByteArray &blockA, const QByteArray &blockB);
    void failed(const QString &err);
private:
    quint16 m_vid, m_pid;
    int m_baud;
};

// QML facade (context property `veroval`): download measurements from the
// Veroval BPM (Prolific PL2303, binary A5/A6 protocol at 19200 baud), parse the
// records and expose them + a CSV export. The raw capture is kept for
// verifying/adjusting the record layout against a specific device.
class Veroval : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QVariantList measurements READ measurements NOTIFY measurementsChanged)
    Q_PROPERTY(int count READ count NOTIFY measurementsChanged)
    Q_PROPERTY(QString rawHex READ rawHex NOTIFY rawHexChanged)
    Q_PROPERTY(int baud READ baud WRITE setBaud NOTIFY baudChanged)
    // Which person the chart is currently showing (1 or 2). Persisted.
    Q_PROPERTY(int chartPerson READ chartPerson WRITE setChartPerson NOTIFY chartPersonChanged)
    // Bumped on every P1/P2 assignment. Reassigning does not change the list
    // itself, and re-emitting measurementsChanged for it would rebuild the
    // whole model — which scrolls the list back to the top under the user's
    // finger. Views that care about the split watch this instead.
    Q_PROPERTY(int personRevision READ personRevision NOTIFY personRevisionChanged)

public:
    explicit Veroval(QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    QString statusText() const { return m_status; }
    QVariantList measurements() const { return m_measurements; }
    int count() const { return m_measurements.size(); }
    QString rawHex() const { return m_rawHex; }
    int baud() const { return m_baud; }
    void setBaud(int b);
    int chartPerson() const { return m_chartPerson; }
    void setChartPerson(int person);
    int personRevision() const { return m_personRevision; }

    // Move a reading to person 1 or 2. The device stamps every record with the
    // memory slot it was stored in, but readings do land in the wrong one, so
    // this override lives in the archive and survives further downloads (the
    // dedup key still uses the device's own user byte).
    Q_INVOKABLE void assignPerson(int index, int person);

    Q_INVOKABLE void download();
    // Re-parse the last raw capture with explicit offsets (for tuning against a
    // device whose layout differs); recordLen/base default to the known BPM25.
    Q_INVOKABLE void reparse(int base, int recordLen);
    // Write CSV to Documents; returns the file path (empty on failure).
    Q_INVOKABLE QString exportCsv();

    // Named archive files: save the whole archive to Documents (returns path),
    // and load a file — merging into the archive (default) or replacing it.
    Q_INVOKABLE QString saveToFile();
    Q_INVOKABLE void loadFromFile(const QString &path, bool merge);
    // Clear the whole archive.
    Q_INVOKABLE void clearArchive();
    // Reserve a timestamped .jpg path under Documents for the chart export
    // (QML grabs the chart and saves to it).
    Q_INVOKABLE QString reserveImagePath();
    // Let QML surface a transient banner via the same channel.
    Q_INVOKABLE void notify(const QString &msg) { emit actionInfo(msg); }

signals:
    void busyChanged();
    void statusTextChanged();
    void measurementsChanged();
    void rawHexChanged();
    void baudChanged();
    void chartPersonChanged();
    void personRevisionChanged();
    void actionError(const QString &message);
    void actionInfo(const QString &message);

private slots:
    void onWorkerProgress(const QString &msg);
    void onWorkerFinished(const QByteArray &blockA, const QByteArray &blockB);
    void onWorkerFailed(const QString &err);

private:
    void setStatus(const QString &s);
    QVariantList parseBlocks(int base, int recordLen) const;        // parse m_blocks -> records
    void parseBlock(QVariantList &out, const QByteArray &raw, int base, int recordLen) const;
    int mergeRecords(const QVariantList &recs);                     // returns #added; sorts + emits
    void rebuildRawHex();
    void saveData() const;      // persist the archive to AppData
    void loadData();            // restore it on startup
    void saveSettings() const;  // UI state that is not measurement data
    void loadSettings();
    QString dataFile() const;
    QString settingsFile() const;
    static QString keyFor(const QVariantMap &m);                    // user:epoch dedup key
    // Person shown for a reading: the manual override if there is one, else
    // the memory slot the device stored it in.
    static int personOf(const QVariantMap &m);

    bool m_busy = false;
    int m_baud = 19200;
    int m_chartPerson = 1;
    int m_personRevision = 0;
    QString m_status;
    QString m_rawHex;
    QList<QByteArray> m_blocks;     // [A5=person1, A6=person2]
    QVariantList m_measurements;
    VeroWorker *m_worker = nullptr;
};

#endif // VEROVAL_H
