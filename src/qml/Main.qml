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

    // LogosTextField propagates `enabled` to its inner TextInput but ships no
    // disabled STYLING, unlike LogosComboBox/LogosCheckbox — so a frozen field
    // stays visually indistinguishable from an editable one and invites the
    // operator to type into it. 0.5 is the design system's own convention for
    // disabled inputs (LogosCheckbox.qml:37, LogosRadioButton.qml:34).
    component ConfigField: LogosTextField {
        opacity: enabled ? 1.0 : 0.5
    }

    QtObject {
        id: d
        readonly property string mod: "verified_proxy_ui"
        readonly property var backend: (typeof logos !== "undefined" && logos) ? logos.module(mod) : null
        readonly property bool ready: backend !== null

        // The module's own network table. Parsed defensively: the property is
        // empty until the fetch returns, and a view that throws here renders
        // nothing at all.
        readonly property var networks: {
            if (!ready || !backend.networksJson) return []
            try { return JSON.parse(backend.networksJson) } catch (e) { return [] }
        }
        // The proxy runs ONE chain: there is a single Context and a single
        // `network` in its config, and the module refuses to reconfigure while
        // running. So the whole configuration section is read-only while it is
        // live — leaving fields editable would let an operator change a value
        // that silently does not take effect.
        readonly property bool locked: ready && (backend.busy || backend.running)

        function profileFor(name) {
            for (var i = 0; i < networks.length; ++i)
                if (networks[i].name === name) return networks[i]
            return null
        }

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

    // Repopulate the form from the last applied config. Runs once, and only
    // once BOTH the network table and the saved config are available — the
    // table arrives asynchronously and the selector's model is empty until it
    // does, so restoring earlier would silently drop the network.
    property bool configRestored: false
    function restoreConfig() {
        if (configRestored || !d.ready) return
        if (d.networks.length === 0) return
        var raw = d.backend.configJson
        if (!raw) return
        var c
        try { c = JSON.parse(raw) } catch (e) { configRestored = true; return }
        configRestored = true

        var names = d.networks.map(function(n) { return n.name })
        var idx = names.indexOf(c.network)
        if (idx >= 0) {
            // Set appliedNetwork FIRST so the selector's change handler sees no
            // change and does not helpfully clear the root we are restoring.
            networkBox.appliedNetwork = c.network
            networkBox.currentIndex = idx
        }
        if (c.beaconApiUrls && c.beaconApiUrls.length)    beaconField.text = c.beaconApiUrls[0]
        if (c.executionApiUrls && c.executionApiUrls.length) execField.text = c.executionApiUrls[0]
        if (c.trustedBlockRoot) rootField.text = c.trustedBlockRoot
        if (c.keepAlive) {
            var k = ["interval", "continuous", "off"].indexOf(c.keepAlive)
            if (k >= 0) keepAliveBox.currentIndex = k
        }
        if (c.httpServer) {
            httpEnabled.checked = !!c.httpServer.enabled
            if (c.httpServer.port) portField.text = String(c.httpServer.port)
        }
        logView.append("restored the last used configuration (" + c.network + ")")
    }
    Component.onCompleted: restoreConfig()

    Connections {
        target: d.backend
        // Deliberately no logging here. The backend already emits a logLine for
        // every outcome — success from log(), failure from setError() — so
        // appending again here printed each one twice.
        function onLogLine(l)                 { logView.append(l) }
        function onNetworksJsonChanged()      { root.restoreConfig() }
        function onConfigJsonChanged()        { root.restoreConfig() }
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small
                        LogosText { text: "Configuration"; font.weight: Theme.typography.weightBold }
                        LogosText {
                            visible: d.locked
                            text: "— read-only while running; press Stop to change it"
                            color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText
                        }
                        Item { Layout.fillWidth: true }
                    }

                    GridLayout {
                        columns: 2
                        columnSpacing: Theme.spacing.small
                        rowSpacing: Theme.spacing.small
                        Layout.fillWidth: true

                        LogosText { text: "Network"; color: Theme.palette.textTertiary }
                        LogosComboBox {
                            id: networkBox
                            Layout.fillWidth: true
                            enabled: !d.locked
                            // Straight from the module's whitelist. Hardcoding
                            // it here would be a crash waiting to happen:
                            // `network` is a value that reaches a quit() inside
                            // Nim when upstream does not recognise it, taking
                            // the whole host process down, so this list must
                            // never be able to drift from the module's.
                            model: d.networks.map(function(n) { return n.name })

                            // Every field on this row is chain-specific: a
                            // trusted root names a block on ONE chain, and a
                            // beacon or execution URL serves ONE chain. Carrying
                            // any of them across a network change builds a config
                            // that cannot bootstrap, and whose failure arrives
                            // long after the change that caused it.
                            property string appliedNetwork: ""
                            onCurrentTextChanged: {
                                if (currentText === "") return
                                var p = d.profileFor(currentText)
                                var changed = appliedNetwork !== "" && currentText !== appliedNetwork

                                if (changed) {
                                    rootField.text = ""
                                    // Overwrite rather than merge, and CLEAR when
                                    // the module offers no default — leaving the
                                    // previous chain's URLs in place is exactly
                                    // the mismatch this is here to prevent.
                                    beaconField.text = p ? p.beaconApiUrl : ""
                                    execField.text   = p ? p.executionApiUrl : ""
                                    logView.append("network → " + currentText
                                        + (p && p.beaconApiUrl
                                           ? ": endpoints set to the defaults, trusted root cleared"
                                           : ": no default endpoints for this network — set them yourself"))
                                } else if (appliedNetwork === "" && p) {
                                    // First population, once the module answers.
                                    beaconField.text = p.beaconApiUrl
                                    execField.text   = p.executionApiUrl
                                }
                                appliedNetwork = currentText
                            }
                        }

                        LogosText { text: "Beacon API"; color: Theme.palette.textTertiary }
                        ConfigField {
                            id: beaconField
                            Layout.fillWidth: true
                            enabled: !d.locked
                            // No hardcoded default: it comes from the module's
                            // network table, which is where the verified pairs
                            // live.
                            placeholderText: "https://…  (must serve the light-client REST API)"
                        }

                        LogosText { text: "Execution API"; color: Theme.palette.textTertiary }
                        ConfigField {
                            id: execField
                            Layout.fillWidth: true
                            enabled: !d.locked
                            placeholderText: "https:// or wss://  (must support eth_getProof)"
                        }

                        LogosText { text: "Trusted root"; color: Theme.palette.textTertiary }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.small
                            ConfigField {
                                id: rootField
                                Layout.fillWidth: true
                                enabled: !d.locked
                                placeholderText: "0x… 32-byte hex — the root of trust"
                            }
                            LogosButton {
                                text: "Fetch finalized"
                                enabled: !d.locked
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
                                enabled: !d.locked
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
                                enabled: !d.locked
                            }
                            ConfigField {
                                id: portField
                                enabled: httpEnabled.checked && !d.locked
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
                        // ONE action. There is no separate "Configure" step:
                        // the module's start() runs the config it has STORED,
                        // so a commit step the operator can skip means an
                        // edited form silently starts the previous settings.
                        LogosButton {
                            text: "Start"
                            variant: LogosButton.Variant.Primary
                            enabled: d.ready && !d.backend.busy && !d.backend.running
                                     && rootField.text.trim() !== ""
                                     && beaconField.text.trim() !== "" && execField.text.trim() !== ""
                            onClicked: d.backend.applyAndStart(root.buildConfig())
                        }
                        LogosButton {
                            text: "Stop"
                            enabled: d.ready && !d.backend.busy && d.backend.running
                            onClicked: d.backend.stop()
                        }
                        LogosText {
                            // Start has several preconditions and a disabled
                            // button explains none of them. The trusted root is
                            // the one that is routinely empty — changing network
                            // clears it, because it names a block on one chain.
                            visible: !d.locked && d.ready && rootField.text.trim() === ""
                            Layout.alignment: Qt.AlignVCenter
                            text: "needs a trusted root — press Fetch finalized, or paste one"
                            color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText
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
                        LogosText {
                            // The module keeps running the config it was given,
                            // so after switching the selector this panel is
                            // still describing the PREVIOUS chain. Saying so
                            // beats showing a chain id that contradicts the
                            // form directly above it.
                            visible: d.ready && d.backend.configuredNetwork !== ""
                                     && d.backend.configuredNetwork !== networkBox.currentText
                            text: "— " + (d.ready ? d.backend.configuredNetwork : "")
                                  + ", not the selected network"
                            color: Theme.palette.warning
                            font.pixelSize: Theme.typography.secondaryText
                        }
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
