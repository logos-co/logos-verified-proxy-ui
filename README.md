# logos-verified-proxy-ui

Basecamp panel for [`verified_proxy_module`](https://github.com/logos-co/logos-verified-proxy-module):
configure it, start and stop it, watch its state, and make verified calls.

A `ui_qml` module — a QML view (`src/qml/Main.qml`) over a small C++ backend
(`src/VerifiedProxyBackend.{h,cpp}`) whose QML-facing surface is the QtRO
contract in `src/VerifiedProxyBackend.rep`.

```bash
nix build && nix build '.#lgx'
```

## Three decisions worth knowing

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
