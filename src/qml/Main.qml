import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

// Management panel for verified_proxy_module: configure, start, stop, watch
// state, and make a few verified calls.
//
// Built from Logos.Controls against Logos.Theme, like every other panel in the
// app. Nothing has to be declared to get them: the design system is compiled
// into the HOST binary as static qt_add_qml_module targets registered under
// qrc:/qt/qml, and a ui_qml view is loaded by the host's own QQmlEngine (a
// QQuickWidget in Basecamp) — ui-host has no QQmlEngine at all. So there is no
// dependency to add in metadata.json and nothing staged into the .lgx.
//
// Two things NOT to do here, both of which break at runtime rather than at
// build time: do not ship a src/qml/qmldir (the builder generates one carrying
// this module's private URI, and overwriting it lets Qt's process-global type
// cache cross-match another plugin's same-named types), and do not create a
// src/qml/Logos/ directory (the host's RestrictedUrlInterceptor reserves that
// prefix case-insensitively and will refuse to resolve anything under it).
Rectangle {
    id: root
    implicitWidth: 900
    implicitHeight: 720
    color: Theme.palette.background

    // Set by onCallFinished. A binding, not an imperative colour write — the
    // old `resultBox.color = …` permanently destroyed the declared binding the
    // first time a call completed.
    property bool lastCallOk: true

    // Whichever of the method dropdown and the custom field is active.
    readonly property string activeMethod:
        methodBox.currentText === "custom…" ? customMethod.text.trim() : methodBox.currentText

    QtObject {
        id: d
        readonly property string mod: "verified_proxy_ui"
        readonly property var backend: (typeof logos !== "undefined" && logos) ? logos.module(mod) : null
        readonly property bool ready: backend !== null

        function stateColour(s) {
            if (s === "running")  return Theme.palette.success
            if (s === "degraded") return Theme.palette.warning
            if (s === "error" || s === "unavailable") return Theme.palette.error
            if (s === "starting" || s === "stopping") return Theme.palette.info
            return Theme.palette.textTertiary
        }
    }

    // ── the config the form builds ──────────────────────────────────────
    function buildConfig() {
        var cfg = {
            "network": networkBox.currentText,
            "trustedBlockRoot": rootField.text.trim(),
            "executionApiUrls": [ execField.text.trim() ],
            "beaconApiUrls": [ beaconField.text.trim() ],
            "keepAlive": keepAliveBox.currentText,
            "logLevel": "INFO"
        }
        if (httpEnabled.checked) {
            cfg["httpServer"] = {
                "enabled": true,
                "host": "127.0.0.1",
                "port": parseInt(portField.text, 10)
            }
        }
        return JSON.stringify(cfg)
    }

    // Asks the backend, which asks the module. Basecamp sandboxes ui_qml
    // plugins away from the network, so an XMLHttpRequest from here is refused
    // outright — and a view is the wrong place for an outbound request anyway.
    // The module answers on finalizedRootFetched.
    //
    // Note this is a convenience, not a trust anchor: a root taken from the
    // same endpoint being verified proves nothing. For anything holding real
    // value, obtain the root independently and paste it in.
    function fetchFinalizedRoot() {
        var base = beaconField.text.trim()
        if (!base) { logView.append("beacon URL is empty"); return }
        d.backend.fetchFinalizedRoot(base)
    }

    Connections {
        target: d.backend
        // Deliberately no logging here. The backend already emits a logLine for
        // every outcome — success from log(), failure from setError() — so
        // appending again here printed each one twice.
        function onLogLine(l)                 { logView.append(l) }
        function onFinalizedRootFetched(ok, root, error) {
            if (ok) rootField.text = root
        }
        function onCallFinished(method, ok, result) {
            resultBox.text = result
            root.lastCallOk = ok
            logView.append((ok ? "← " : "✗ ") + method)
        }
    }

    LogosScrollView {
        id: sv
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        // LogosScrollView hard-binds contentWidth to its own width; this panel
        // wants the width inside the scrollbar gutter.
        contentWidth: availableWidth

        ColumnLayout {
            width: sv.availableWidth
            spacing: Theme.spacing.medium

            // ── header ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosText {
                    text: "Verified Proxy"
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightBold
                }
                LogosBadge {
                    text: d.ready ? d.backend.state : "no module"
                    color: d.stateColour(d.ready ? d.backend.state : "unavailable")
                }
                Item { Layout.fillWidth: true }
                LogosSpinner {
                    running: d.ready && d.backend.busy
                    visible: running
                    implicitWidth: 22
                    implicitHeight: 22
                }
                LogosText {
                    visible: d.ready && d.backend.endpoint !== ""
                    text: d.ready ? d.backend.endpoint : ""
                    // success, not primary: this only appears while the
                    // endpoint is actually serving, so it is a liveness
                    // signal rather than a brand accent.
                    color: Theme.palette.success
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            // ── configuration ───────────────────────────────────────────
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small

                    LogosText { text: "Configuration"; font.weight: Theme.typography.weightBold }

                    GridLayout {
                        columns: 2
                        columnSpacing: Theme.spacing.small
                        rowSpacing: Theme.spacing.small
                        Layout.fillWidth: true

                        LogosText { text: "Network"; color: Theme.palette.textTertiary }
                        LogosComboBox {
                            id: networkBox
                            Layout.fillWidth: true
                            // Exactly the three the library supports. Anything
                            // else reaches a quit() inside Nim and would take
                            // the whole host process down, so this is a
                            // dropdown rather than a text field on purpose.
                            model: ["sepolia", "mainnet", "hoodi"]
                        }

                        LogosText { text: "Beacon API"; color: Theme.palette.textTertiary }
                        LogosTextField {
                            id: beaconField
                            Layout.fillWidth: true
                            text: "https://lodestar-sepolia.chainsafe.io"
                            placeholderText: "https://…  (must serve the light-client REST API)"
                        }

                        LogosText { text: "Execution API"; color: Theme.palette.textTertiary }
                        LogosTextField {
                            id: execField
                            Layout.fillWidth: true
                            text: "https://ethereum-sepolia-rpc.publicnode.com"
                            placeholderText: "https:// or wss://  (must support eth_getProof)"
                        }

                        LogosText { text: "Trusted root"; color: Theme.palette.textTertiary }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small
                            LogosTextField {
                                id: rootField
                                Layout.fillWidth: true
                                placeholderText: "0x… 32-byte hex — the root of trust"
                            }
                            LogosButton {
                                text: "Fetch finalized"
                                onClicked: root.fetchFinalizedRoot()
                            }
                        }

                        LogosText { text: "Keep-alive"; color: Theme.palette.textTertiary }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small
                            LogosComboBox {
                                id: keepAliveBox
                                Layout.preferredWidth: 160
                                // "off" is offered last and never preselected:
                                // without a heartbeat the verified head goes
                                // BACKWARDS (measured: -39 blocks over 5 min).
                                model: ["interval", "continuous", "off"]
                            }
                            LogosBadge {
                                visible: keepAliveBox.currentText === "off"
                                text: "head regresses without a heartbeat"
                                iconSource: LogosIcons.warning
                                color: Theme.palette.warning
                            }
                            Item { Layout.fillWidth: true }
                        }

                        LogosText { text: "JSON-RPC endpoint"; color: Theme.palette.textTertiary }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small
                            // LogosCheckbox ships its own themed LogosText
                            // contentItem, which is exactly why the old
                            // hand-rolled override existed.
                            LogosCheckbox {
                                id: httpEnabled
                                text: "serve on 127.0.0.1"
                                checked: false
                            }
                            LogosTextField {
                                id: portField
                                enabled: httpEnabled.checked
                                text: "8545"
                                Layout.preferredWidth: 90
                                // With a validator set, LogosTextField paints
                                // its border with the error colour while the
                                // input is unacceptable.
                                validator: IntValidator { bottom: 1; top: 65535 }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small
                        LogosButton {
                            text: "Configure"
                            variant: LogosButton.Variant.Primary
                            enabled: d.ready && !d.backend.busy && rootField.text.trim() !== ""
                            onClicked: d.backend.configure(root.buildConfig())
                        }
                        LogosButton {
                            text: "Start"
                            variant: LogosButton.Variant.Primary
                            enabled: d.ready && !d.backend.busy && !d.backend.running
                            onClicked: d.backend.start()
                        }
                        LogosButton {
                            text: "Stop"
                            enabled: d.ready && !d.backend.busy && d.backend.running
                            onClicked: d.backend.stop()
                        }
                        Item { Layout.fillWidth: true }
                        LogosButton {
                            text: "Refresh"
                            leadingIcon.source: LogosIcons.refresh
                            enabled: d.ready
                            onClicked: d.backend.refreshStatus()
                        }
                    }

                    LogosText {
                        visible: d.ready && d.backend.lastError !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: d.ready ? d.backend.lastError : ""
                        color: Theme.palette.error
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }
            }

            // ── state ───────────────────────────────────────────────────
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        LogosText { text: "State"; font.weight: Theme.typography.weightBold }
                        Item { Layout.fillWidth: true }
                        LogosText {
                            text: "chain " + (d.ready ? d.backend.chainId : 0)
                                  + "   head " + (d.ready && d.backend.headBlock !== "" ? d.backend.headBlock : "—")
                            color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText
                        }
                    }

                    LogosButton {
                        text: rawJson.visible ? "Hide raw status" : "Show raw status"
                        trailingIcon.source: rawJson.visible ? LogosIcons.triangleUp : LogosIcons.triangleDown
                        onClicked: rawJson.visible = !rawJson.visible
                    }
                    LogosTextArea {
                        id: rawJson
                        visible: false
                        Layout.fillWidth: true
                        implicitHeight: 200
                        readOnly: true
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textTertiary
                        text: d.ready ? d.backend.statusJson : ""
                    }
                }
            }

            // ── calls ───────────────────────────────────────────────────
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small

                    LogosText { text: "Verified call"; font.weight: Theme.typography.weightBold }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small
                        // LogosComboBox is NOT editable-capable: its contentItem
                        // is a LogosText, not a TextInput, so `editable: true`
                        // silently gives no caret and desyncs editText from
                        // what is displayed — it would submit a method the user
                        // can neither see nor set. The module exposes far more
                        // methods than the presets below, so "custom…" reveals
                        // a real text field instead.
                        LogosComboBox {
                            id: methodBox
                            Layout.preferredWidth: 260
                            model: ["eth_blockNumber", "eth_chainId", "eth_gasPrice",
                                    "eth_getBalance", "eth_getCode", "eth_getBlockByNumber",
                                    "eth_syncing", "custom…"]
                            onCurrentTextChanged: {
                                // Prefill the shape each method expects, so the
                                // panel is usable without consulting the docs.
                                if (currentText === "eth_getBalance" || currentText === "eth_getCode")
                                    paramsField.text = '["0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045","latest"]'
                                else if (currentText === "eth_getBlockByNumber")
                                    paramsField.text = '["latest",false]'
                                else
                                    paramsField.text = "[]"
                            }
                        }
                        LogosTextField {
                            id: customMethod
                            visible: methodBox.currentText === "custom…"
                            Layout.preferredWidth: 220
                            placeholderText: "eth_… / op_…"
                        }
                        LogosTextField {
                            id: paramsField
                            Layout.fillWidth: true
                            text: "[]"
                            placeholderText: "JSON array of params"
                        }
                        LogosButton {
                            text: "Send"
                            variant: LogosButton.Variant.Primary
                            enabled: d.ready && d.backend.running && root.activeMethod !== ""
                            onClicked: d.backend.callRpc(root.activeMethod, paramsField.text)
                        }
                    }

                    LogosTextArea {
                        id: resultBox
                        Layout.fillWidth: true
                        implicitHeight: 130
                        readOnly: true
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.secondaryText
                        color: root.lastCallOk ? Theme.palette.text : Theme.palette.error
                        text: ""
                    }
                }
            }

            // ── log ─────────────────────────────────────────────────────
            LogosFrame {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.small

                contentItem: LogosTextArea {
                    id: logView
                    readOnly: true
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textTertiary
                    text: ""
                    function append(line) { text = text + (text === "" ? "" : "\n") + line }
                }
            }
        }
    }
}
