import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Management panel for verified_proxy_module: configure, start, stop, watch
// state, and make a few verified calls.
//
// Deliberately plain QtQuick.Controls with inline colours rather than
// Logos.Theme: a single unresolved import takes down the WHOLE view, and the
// host routes that qWarning to journald where it is easy to miss. Fewer
// imports, fewer ways to end up staring at an empty pane.
Item {
    id: root
    implicitWidth: 900
    implicitHeight: 720

    readonly property color bg:      "#12151f"
    readonly property color card:    "#1b1f2c"
    readonly property color line:    "#2b3145"
    readonly property color fg:      "#e6e9f0"
    readonly property color muted:   "#8b93a7"
    readonly property color accent:  "#42c48c"
    readonly property color danger:  "#e2555f"

    QtObject {
        id: d
        readonly property string mod: "verified_proxy_ui"
        readonly property var backend: (typeof logos !== "undefined" && logos) ? logos.module(mod) : null
        readonly property bool ready: backend !== null

        function stateColour(s) {
            if (s === "running")  return root.accent
            if (s === "degraded") return "#e8b339"
            if (s === "error" || s === "unavailable") return root.danger
            if (s === "starting" || s === "stopping") return "#5aa9e6"
            return root.muted
        }
    }

    Rectangle { anchors.fill: parent; color: root.bg }

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
                "port": parseInt(portField.text || "8545", 10)
            }
        }
        return JSON.stringify(cfg, null, 2)
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
            resultBox.color = ok ? root.fg : root.danger
            logView.append((ok ? "← " : "✗ ") + method)
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 16
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width - 40
            spacing: 14

            // ── header ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Label {
                    text: "Verified Proxy"
                    color: root.fg
                    font.pixelSize: 22
                    font.bold: true
                }
                Rectangle {
                    radius: 10; height: 22
                    implicitWidth: stateLabel.implicitWidth + 20
                    color: "transparent"
                    border.color: d.stateColour(d.ready ? d.backend.state : "unavailable")
                    border.width: 1
                    Label {
                        id: stateLabel
                        anchors.centerIn: parent
                        text: d.ready ? d.backend.state : "no module"
                        color: d.stateColour(d.ready ? d.backend.state : "unavailable")
                        font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
                BusyIndicator { running: d.ready && d.backend.busy; implicitWidth: 22; implicitHeight: 22 }
                Label {
                    visible: d.ready && d.backend.endpoint !== ""
                    text: d.ready ? d.backend.endpoint : ""
                    color: root.accent
                    font.pixelSize: 12
                }
            }

            // ── configuration ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: root.card; radius: 8; border.color: root.line
                implicitHeight: cfgCol.implicitHeight + 28

                ColumnLayout {
                    id: cfgCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    Label { text: "Configuration"; color: root.fg; font.bold: true }

                    GridLayout {
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8
                        Layout.fillWidth: true

                        Label { text: "Network"; color: root.muted }
                        ComboBox {
                            id: networkBox
                            Layout.fillWidth: true
                            // Exactly the three the library supports. Anything
                            // else reaches a quit() inside Nim and would take
                            // the whole host process down, so this is a
                            // dropdown rather than a text field on purpose.
                            model: ["sepolia", "mainnet", "hoodi"]
                        }

                        Label { text: "Beacon API"; color: root.muted }
                        TextField {
                            id: beaconField
                            Layout.fillWidth: true
                            text: "https://lodestar-sepolia.chainsafe.io"
                            placeholderText: "https://…  (must serve the light-client REST API)"
                        }

                        Label { text: "Execution API"; color: root.muted }
                        TextField {
                            id: execField
                            Layout.fillWidth: true
                            text: "https://ethereum-sepolia-rpc.publicnode.com"
                            placeholderText: "https:// or wss://  (must support eth_getProof)"
                        }

                        Label { text: "Trusted root"; color: root.muted }
                        RowLayout {
                            Layout.fillWidth: true
                            TextField {
                                id: rootField
                                Layout.fillWidth: true
                                placeholderText: "0x… 32-byte hex — the root of trust"
                            }
                            Button { text: "Fetch finalized"; onClicked: root.fetchFinalizedRoot() }
                        }

                        Label { text: "Keep-alive"; color: root.muted }
                        RowLayout {
                            Layout.fillWidth: true
                            ComboBox {
                                id: keepAliveBox
                                // "off" is offered last and never preselected:
                                // without a heartbeat the verified head goes
                                // BACKWARDS (measured: -39 blocks over 5 min).
                                model: ["interval", "continuous", "off"]
                            }
                            Label {
                                visible: keepAliveBox.currentText === "off"
                                text: "⚠ the head regresses without a heartbeat"
                                color: "#e8b339"
                                font.pixelSize: 11
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Label { text: "JSON-RPC endpoint"; color: root.muted }
                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox {
                                id: httpEnabled
                                text: "serve on 127.0.0.1"
                                checked: false
                                // The stock Basic style draws its label in the
                                // default palette colour, which is near-black
                                // on this panel and effectively invisible.
                                contentItem: Label {
                                    text: httpEnabled.text
                                    color: root.fg
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: httpEnabled.indicator.width + httpEnabled.spacing
                                }
                            }
                            TextField {
                                id: portField
                                enabled: httpEnabled.checked
                                text: "8545"
                                implicitWidth: 90
                                validator: IntValidator { bottom: 1; top: 65535 }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Button {
                            text: "Configure"
                            enabled: d.ready && !d.backend.busy && rootField.text.trim() !== ""
                            onClicked: d.backend.configure(root.buildConfig())
                        }
                        Button {
                            text: "Start"
                            enabled: d.ready && !d.backend.busy && !d.backend.running
                            onClicked: d.backend.start()
                        }
                        Button {
                            text: "Stop"
                            enabled: d.ready && !d.backend.busy && d.backend.running
                            onClicked: d.backend.stop()
                        }
                        Item { Layout.fillWidth: true }
                        Button { text: "Refresh"; enabled: d.ready; onClicked: d.backend.refreshStatus() }
                    }

                    Label {
                        visible: d.ready && d.backend.lastError !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: d.ready ? d.backend.lastError : ""
                        color: root.danger
                        font.pixelSize: 12
                    }
                }
            }

            // ── state ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: root.card; radius: 8; border.color: root.line
                implicitHeight: stCol.implicitHeight + 28

                ColumnLayout {
                    id: stCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "State"; color: root.fg; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "chain " + (d.ready ? d.backend.chainId : 0)
                                  + "   head " + (d.ready && d.backend.headBlock !== "" ? d.backend.headBlock : "—")
                            color: root.muted
                            font.pixelSize: 12
                        }
                    }

                    Button {
                        text: rawJson.visible ? "Hide raw status" : "Show raw status"
                        onClicked: rawJson.visible = !rawJson.visible
                    }
                    TextArea {
                        id: rawJson
                        visible: false
                        Layout.fillWidth: true
                        implicitHeight: 200
                        readOnly: true
                        font.family: "monospace"
                        font.pixelSize: 11
                        color: root.muted
                        text: d.ready ? d.backend.statusJson : ""
                    }
                }
            }

            // ── calls ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: root.card; radius: 8; border.color: root.line
                implicitHeight: callCol.implicitHeight + 28

                ColumnLayout {
                    id: callCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    Label { text: "Verified call"; color: root.fg; font.bold: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ComboBox {
                            id: methodBox
                            Layout.preferredWidth: 260
                            editable: true
                            model: ["eth_blockNumber", "eth_chainId", "eth_gasPrice",
                                    "eth_getBalance", "eth_getCode", "eth_getBlockByNumber",
                                    "eth_syncing"]
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
                        TextField {
                            id: paramsField
                            Layout.fillWidth: true
                            text: "[]"
                            placeholderText: "JSON array of params"
                        }
                        Button {
                            text: "Send"
                            enabled: d.ready && d.backend.running
                            onClicked: d.backend.callRpc(methodBox.editText, paramsField.text)
                        }
                    }

                    TextArea {
                        id: resultBox
                        Layout.fillWidth: true
                        implicitHeight: 130
                        readOnly: true
                        font.family: "monospace"
                        font.pixelSize: 11
                        color: root.fg
                        text: ""
                    }
                }
            }

            // ── log ─────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: root.card; radius: 8; border.color: root.line
                implicitHeight: 150

                TextArea {
                    id: logView
                    anchors.fill: parent
                    anchors.margins: 10
                    readOnly: true
                    font.family: "monospace"
                    font.pixelSize: 11
                    color: root.muted
                    text: ""
                    function append(line) { text = text + (text === "" ? "" : "\n") + line }
                }
            }
        }
    }
}
