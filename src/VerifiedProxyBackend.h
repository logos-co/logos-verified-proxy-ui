#pragma once

#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_ui_plugin_context.h"
#include "rep_VerifiedProxyBackend_source.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QElapsedTimer>
#include <QTimer>
#include <QVariantMap>

#ifndef VERIFIED_PROXY_UI_VERSION
#define VERIFIED_PROXY_UI_VERSION "0.0.0-dev"
#endif

/// QML-facing backend for verified_proxy_module.
///
/// Everything here is a thin forward to the module. The one piece of real
/// behaviour is the status poll: see onContextReady().
class VerifiedProxyBackend : public VerifiedProxyBackendSimpleSource,
                             public LogosUiPluginContext {
    Q_OBJECT
public:
    explicit VerifiedProxyBackend(QObject* parent = nullptr);

    void applyAndStart(QString configJson) override;

private:
    /// Second half of applyAndStart(). Never called on its own — start() runs
    /// the config the module has stored, so it is only ever valid straight
    /// after a successful configure().
    void startAfterConfigure();

public:
    void stop() override;
    void refreshStatus() override;
    void fetchFinalizedRoot(QString beaconUrl) override;
    void callRpc(QString method, QString paramsJson) override;

protected:
    void onContextReady() override;

private:
    void setError(const QString& message);
    void log(const QString& line);
    /// Pulls status() and republishes it onto the READONLY properties.
    void pollStatus();

    LogosModules* m_logos = nullptr;
    QTimer* m_pollTimer = nullptr;

    // Liveness watchdog: elapsed time since the last ANSWERED status(), because
    // an unanswered call is not the same as a failed one. When the module went
    // away mid-start, neither the 5s status timeout nor the 150s start timeout
    // ever fired — the callbacks were simply never invoked — so `busy` latched
    // true and disabled Configure, Start, Stop and Send all at once.
    //
    // Scope, measured: this covers a module that stops ANSWERING while this
    // backend lives. It does NOT cover a module process CRASH, because
    // Basecamp tears down ui-host along with it (verified: kill the module
    // process and ui-host exits too), so nothing here is left running to
    // notice. In that case the view keeps its last property values and only
    // the host can report it. The real defence against that is the module not
    // crashing — see the one-thread-per-lifetime fix in proxy_runtime.
    QElapsedTimer m_sinceGoodPoll;
    bool m_declaredUnreachable = false;
};
