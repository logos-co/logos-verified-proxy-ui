#include "VerifiedProxyBackend.h"

#include <QJsonArray>
#include <QJsonParseError>

namespace {

/// Consumer-side timeouts must EXCEED the module's own, or the transport gives
/// up first and the caller sees a bare "timeout" instead of the module's real
/// explanation. The module defaults are startTimeoutMs=120000,
/// callTimeoutMs=30000, drainTimeoutMs=2000 (which stop() can overshoot by up
/// to one pump turn, ~3.3s measured).
constexpr int kStartTimeoutMs = 150000;   // module 120s + slack
constexpr int kCallTimeoutMs  = 45000;    // module  30s + slack
constexpr int kStopTimeoutMs  = 20000;    // drain 2s + overshoot, generously
constexpr int kStatusTimeoutMs = 5000;    // status() never touches the proxy thread

constexpr int kPollIntervalMs = 2000;

QString pretty(const QVariantMap& m) {
    return QString::fromUtf8(
        QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Indented));
}

QString describe(const logos::CallError& e) {
    const QString m = QString::fromStdString(e.message);
    return m.isEmpty() ? QStringLiteral("call failed") : m;
}

} // namespace

VerifiedProxyBackend::VerifiedProxyBackend(QObject* parent)
    : VerifiedProxyBackendSimpleSource(parent) {
    setUiVersion(QStringLiteral(VERIFIED_PROXY_UI_VERSION));
    setState(QStringLiteral("uninitialized"));
    setRunning(false);
    setBusy(false);
    setChainId(0);
}

void VerifiedProxyBackend::onContextReady() {
    // Construct our own LogosModules rather than aliasing &modules(): the
    // generated plugin declares its own LogosModules AFTER this hook runs, so a
    // captured reference would dangle.
    m_logos = new LogosModules(modules().api);

    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(kPollIntervalMs);
    connect(m_pollTimer, &QTimer::timeout, this, [this] { pollStatus(); });
    m_pollTimer->start();

    pollStatus();   // don't make the panel wait a full interval to show anything
}

// ── helpers ─────────────────────────────────────────────────────────────────

void VerifiedProxyBackend::setError(const QString& message) {
    setLastError(message);
    if (!message.isEmpty()) log(QStringLiteral("error: ") + message);
}

void VerifiedProxyBackend::log(const QString& line) { emit logLine(line); }

// ── status polling ──────────────────────────────────────────────────────────

void VerifiedProxyBackend::pollStatus() {
    if (!m_logos) return;
    m_logos->verified_proxy_module.statusAsyncResult(
        [this](logos::AsyncResult<QVariantMap> r) {
            if (!r.ok()) {
                // Don't spam lastError from a background poll — the module may
                // simply not be loaded yet. Reflect it in `state` instead.
                setState(QStringLiteral("unavailable"));
                setRunning(false);
                return;
            }
            const QVariantMap s = r.value;
            setState(s.value("state").toString());
            // "degraded" means up-but-heartbeat-failing, so it is still a
            // live, stoppable process. Treating it as not-running would
            // disable Stop and re-enable Start on exactly the proxy the
            // operator most needs to restart. Health is shown by the state
            // badge and lastError, not by this flag.
            const QString st = s.value("state").toString();
            setRunning(st == QLatin1String("running") || st == QLatin1String("degraded"));
            setChainId(s.value("chainId").toInt());
            setHeadBlock(s.value("head").toMap().value("blockNumber").toString());
            setEndpoint(s.value("httpServer").toMap().value("endpoint").toString());
            setStatusJson(pretty(s));
            emit statusUpdated(s);
        },
        Timeout(kStatusTimeoutMs));
}

void VerifiedProxyBackend::refreshStatus() { pollStatus(); }

// ── lifecycle ───────────────────────────────────────────────────────────────

void VerifiedProxyBackend::configure(QString configJson) {
    if (!m_logos) return;

    QJsonParseError perr{};
    const QJsonDocument doc = QJsonDocument::fromJson(configJson.toUtf8(), &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
        // Fail locally rather than shipping malformed JSON across IPC: the
        // module would reject it anyway, with a less specific message.
        const QString e = QStringLiteral("config is not a JSON object: ") + perr.errorString();
        setError(e);
        emit configured(false, e);
        return;
    }

    setConfigJson(configJson);
    setBusy(true);
    m_logos->verified_proxy_module.configureAsyncResult(
        doc.object().toVariantMap(),
        [this](logos::AsyncResult<LogosResult> r) {
            setBusy(false);
            if (!r.ok())            { setError(describe(r.error));       emit configured(false, describe(r.error)); return; }
            if (!r.value.success)   { const QString e = r.value.error.toString();
                                      setError(e);                       emit configured(false, e); return; }
            setError({});
            log(QStringLiteral("configured"));
            emit configured(true, {});
            pollStatus();
        },
        Timeout(kCallTimeoutMs));
}

void VerifiedProxyBackend::start() {
    if (!m_logos) return;
    setBusy(true);
    log(QStringLiteral("starting — the light client must bootstrap, this can take a while"));

    // ASYNC deliberately: start() blocks in the module until the light client
    // initialises (up to its startTimeoutMs, 120s by default). Calling it
    // synchronously would freeze the UI thread for that whole time.
    m_logos->verified_proxy_module.startAsyncResult(
        [this](logos::AsyncResult<LogosResult> r) {
            setBusy(false);
            if (!r.ok())          { setError(describe(r.error));   emit startFinished(false, describe(r.error)); return; }
            if (!r.value.success) { const QString e = r.value.error.toString();
                                    setError(e);                    emit startFinished(false, e); return; }
            setError({});
            log(QStringLiteral("started"));
            emit startFinished(true, {});
            pollStatus();
        },
        Timeout(kStartTimeoutMs));
}

void VerifiedProxyBackend::stop() {
    if (!m_logos) return;
    setBusy(true);
    m_logos->verified_proxy_module.stopAsyncResult(
        [this](logos::AsyncResult<LogosResult> r) {
            setBusy(false);
            if (!r.ok())          { setError(describe(r.error));   emit stopFinished(false, describe(r.error)); return; }
            if (!r.value.success) { const QString e = r.value.error.toString();
                                    setError(e);                    emit stopFinished(false, e); return; }
            setError({});
            log(QStringLiteral("stopped"));
            emit stopFinished(true, {});
            pollStatus();
        },
        Timeout(kStopTimeoutMs));
}

// ── calls ───────────────────────────────────────────────────────────────────

void VerifiedProxyBackend::fetchFinalizedRoot(QString beaconUrl) {
    if (!m_logos) return;

    // Forwarded to the module rather than fetched here: Basecamp's sandbox
    // blocks network access from ui_qml plugins, and rightly so — the view is
    // the least trustworthy place to put an outbound request.
    log(QStringLiteral("fetching finalized root from ") + beaconUrl);
    m_logos->verified_proxy_module.fetchFinalizedRootAsyncResult(
        beaconUrl,
        [this](logos::AsyncResult<LogosResult> r) {
            if (!r.ok()) {
                emit finalizedRootFetched(false, {}, describe(r.error));
                log(QStringLiteral("error: ") + describe(r.error));
                return;
            }
            if (!r.value.success) {
                const QString e = r.value.error.toString();
                emit finalizedRootFetched(false, {}, e);
                log(QStringLiteral("error: ") + e);
                return;
            }
            const QVariantMap m = r.value.value.toMap();
            const QString root = m.value(QStringLiteral("root")).toString();
            const QString slot = m.value(QStringLiteral("slot")).toString();
            emit finalizedRootFetched(true, root, {});
            log(QStringLiteral("finalized root ") + root
                + (slot.isEmpty() ? QString() : QStringLiteral(" (slot ") + slot + QLatin1Char(')')));
        },
        Timeout(kCallTimeoutMs));
}

void VerifiedProxyBackend::callRpc(QString method, QString paramsJson) {
    if (!m_logos) return;

    if (paramsJson.trimmed().isEmpty()) paramsJson = QStringLiteral("[]");
    QJsonParseError perr{};
    const QJsonDocument doc = QJsonDocument::fromJson(paramsJson.toUtf8(), &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isArray()) {
        const QString e = QStringLiteral("params must be a JSON array — ") + perr.errorString();
        emit callFinished(method, false, e);
        return;
    }

    log(QStringLiteral("→ ") + method + QLatin1Char(' ') + paramsJson);
    m_logos->verified_proxy_module.rpcAsyncResult(
        method, doc.array().toVariantList(),
        [this, method](logos::AsyncResult<LogosResult> r) {
            if (!r.ok()) { emit callFinished(method, false, describe(r.error)); return; }
            if (!r.value.success) {
                emit callFinished(method, false, r.value.error.toString());
                return;
            }
            // The value is whatever the library returned — a hex string, a
            // number, or an object. Render all three readably.
            const QVariant v = r.value.value;
            QString rendered;
            if (v.canConvert<QVariantMap>() && v.typeId() == QMetaType::QVariantMap)
                rendered = pretty(v.toMap());
            else if (v.typeId() == QMetaType::QVariantList)
                rendered = QString::fromUtf8(
                    QJsonDocument(QJsonArray::fromVariantList(v.toList())).toJson(QJsonDocument::Indented));
            else
                rendered = v.toString();
            emit callFinished(method, true, rendered);
        },
        Timeout(kCallTimeoutMs));
}
