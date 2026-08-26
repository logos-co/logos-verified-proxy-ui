# logos-verified-proxy-ui

Basecamp panel for [`verified_proxy_module`](https://github.com/logos-co/logos-verified-proxy-module):
configure it, start and stop it, watch its state, and make verified calls.

A `ui_qml` module — a QML view (`src/qml/Main.qml`) over a small C++ backend
(`src/VerifiedProxyBackend.{h,cpp}`) whose QML-facing surface is the QtRO
contract in `src/VerifiedProxyBackend.rep`.

```bash
nix build && nix build '.#lgx'
```

## Four decisions worth knowing

**The panel is built from `Logos.Controls` on `Logos.Theme`.** Nothing declares
that dependency, and nothing needs to: the design system is compiled into the
*host* binary as static `qt_add_qml_module` targets registered under
`qrc:/qt/qml`, and a `ui_qml` view is loaded by the host's own `QQmlEngine` (a
`QQuickWidget` in Basecamp) — `ui-host` has no `QQmlEngine` at all. So there is
no input in `flake.nix`, no key in `metadata.json`, and nothing staged into the
`.lgx`. Two things will break it at *runtime* rather than at build time: shipping
your own `src/qml/qmldir` (the builder generates one carrying this module's
private URI, and overwriting it lets Qt's process-global type cache cross-match
another plugin's same-named types), and creating a `src/qml/Logos/` directory
(the host's `RestrictedUrlInterceptor` reserves that prefix case-insensitively).

**State is polled, not subscribed.** A UI plugin's event subscription is
one-shot and is refused outright if it is armed before the registry handshake,
with no retry — so a panel built on subscriptions silently shows nothing when it
loses that race. `status()` is cheap and never touches the proxy thread, so the
backend polls it every 2s instead. Simpler, and immune to that race.

**Every module call is asynchronous.** `start()` blocks inside the module until
the light client bootstraps — up to `startTimeoutMs`, 120s by default. Calling
it synchronously would freeze the UI for that whole time, so the backend uses
the generated `*AsyncResult` twins throughout. The consumer-side timeouts are
deliberately *longer* than the module's own (150s vs 120s for start), so the
module's real error message wins the race rather than a bare transport timeout.

**The form constrains what can be typed.** `network` is a dropdown of exactly
`sepolia`/`mainnet`/`hoodi`, because any other value reaches a `quit()` inside
the Nim library and would take the whole host process down. `keepAlive` never
preselects `off`, and warns when chosen: without a heartbeat the verified head
goes *backwards* (measured: −39 blocks over a 5-minute idle).

## Using it

Set the beacon and execution URLs, press **Fetch finalized** to pull a trusted
block root, then **Configure** → **Start**. The panel shows state, chain id and
head block, with the raw `status()` payload behind a toggle.

The execution provider must support `eth_getProof`, and state-reading calls
(`eth_getBalance`, `eth_getCode`) additionally need a provider whose proof
window reaches the light client's finalized header — free public endpoints
generally do not. Proof-free calls (`eth_blockNumber`, `eth_chainId`,
`eth_gasPrice`, `eth_getBlockByNumber`) work anywhere.

Tick **serve on 127.0.0.1** to have the module expose its own JSON-RPC endpoint;
the URL then appears in the header and via `localEndpoint()`.

## Pre-flight checks

`nix build` proves nothing about the QML: the builder only copies `src/qml`, so
it is green for `import Logos.Thmee`. An unresolved import takes down the *whole*
view, and the only message that names the real cause goes to `qWarning` — the
macOS unified log for a desktop-launched app, not any terminal you are watching.
Run these instead. `DS` points at the design system's source tree; use the
oldest revision you must satisfy, since the host, not this repo, decides which
one is loaded.

```bash
DS=../logos-design-system/src/qml
QTQML=$(dirname $(dirname $(readlink -f $(command -v qmllint))))/lib/qt-6/qml
qmllint -I "$QTQML" -I "$DS" -W 0 --unqualified disable src/qml/Main.qml
```

`-W 0` is what makes warnings set the exit code; `--unqualified disable` is
required because `logos` is a host-injected context property qmllint cannot see.
This catches unresolved imports and misspelled type names — but **not** misspelled
theme tokens: `Theme.palette` is declared `var`, so `Theme.palette.nonsense`
evaluates to `undefined` silently, with no error and no warning. Check those by eye.

Then instantiate it for real, which catches what the linter cannot — style
customization rejections and missing runtime properties:

```bash
QT_QUICK_CONTROLS_STYLE=Basic QT_QPA_PLATFORM=offscreen qml -I "$QTQML" -I "$DS" src/qml/Main.qml
```

Forcing the `Basic` style is load-bearing: under the native macOS style the
design system's own `contentItem` overrides are rejected. Both hosts already set
it, but a bare `qml` does not. If icons report *"Unsupported image format"*, your
`qml` has no Qt SVG plugin — add `QT_PLUGIN_PATH` from a **matching** qtsvg
version; mixing Qt minor versions produces far more confusing failures.

Neither gate exercises the sandbox or the host's real design-system revision, so
finish by installing the `.lgx` and launching Basecamp from a terminal with
`QT_FORCE_STDERR_LOGGING=1`.
