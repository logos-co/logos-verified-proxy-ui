#pragma once

#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_ui_plugin_context.h"
#include "rep_VerifiedProxyBackend_source.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QString>
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

    void configure(QString configJson) override;
    void start() override;
    void stop() override;
    void refreshStatus() override;
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
};
