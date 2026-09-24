# Blend lifecycle QML tests

From the worktree root (all fixtures are offline, with no `logos` context):

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /home/alisher/Qt/6.9.3/gcc_64/bin/qmltestrunner \
  -input tests/qml \
  -import /home/alisher/basecamp/refs/logos-design-system/src/qml
python3 tests/qml_integration_test.py
```

`BlendCoreProgress` dynamically instantiates the **production** component. It checks expansion/collapse, preservation of user choice across polls, all three action signals, disabled actions during busy, persistent errors, unknown fallback strip, 17 state-name fixtures at 320/920 px, geometry bounds, and nonempty rendered image grabs. These are presentation fixtures, not validation of the backend reducer's state decisions.

`BlendLifecycleController` instantiates the production controller with fake QtRO endpoints: read overlap guard, deadline, stale reply rejection, explicit-only repair, duplicate repair guard, acknowledgement copy, and errors surviving subsequent polls. No real backend is instantiated. Python guards dashboard placement, controller wiring and unsafe legacy copy; it is not a runtime test of the whole app/modal.

TDD: missing production component/controller and unsafe integration copy were observed failing before implementation; unknown fallback strip regression was separately observed failing then fixed.

Known runner warning: reference design system Theme uses QSettings without organization identifiers in stock qmltestrunner (two initialization warnings). Component tests otherwise pass. The reference LogosFrame has no `radius` property, unlike the application's existing dashboard expectations; the new panel uses a custom background Rectangle, compatible with both.

## Rendered screenshots / packaged verification

Run `tests/qml/BlendCoreHarness.qml` in the Qt QML runner, with the same design-system import path. It loads only the production panel with a missing-binding fixture and signal-only fake action handlers (no mutations). The parent window exposes `panelWidth`, `fixture`, and `componentUrl`; set `componentUrl` to the unpacked LGX's **actual** `controls/BlendCoreProgress.qml` URL to prove packaging. The loader item exposes `expanded`, `busy`, `resultText`, and `resultError` for screenshot variants. At 320 px labels elide inside individual chevrons; hover reveals full stage/state. Capture blocked expanded, healthy collapsed, error-result collapsed, and busy/narrow variants. Verify the full dashboard with the parent's isolated packaged harness to confirm node-panel adjacency and modal integration.

Do not run `BlockchainView.qml` standalone against a real logos backend for these tests. Live epoch transitions, actual repair and withdrawal, and installation remain manual acceptance outside this suite.

## BlendView tab test (tst_BlendView.qml)

Covers the Blend tab that replaced the modal: component loads to Ready (imports +
qmldir resolve — the headless catch for QML-load errors the nix build misses), the
phase→step-indicator mapping, the openWallet shortcut, that it is not a dismissable
modal, and the mutation/invalidation invariants carried over from the modal. Needs a
**current** design system (LogosFrame `radius`); the older `~/basecamp/refs` DS lacks
it — point `-import` at a recent logos-design-system checkout/build.
