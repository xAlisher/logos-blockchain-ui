import QtQuick
import QtQuick.Window
import Logos.Theme

// No logos context and no real backend. Change componentUrl to packaged QML to
// verify packaging. Inspector may set fixture, panelWidth and expanded on item.
Window {
    id: harness
    visible: true
    width: 1000; height: 650
    color: Theme.palette.background
    property url componentUrl: "../../src/qml/controls/BlendCoreProgress.qml"
    property int panelWidth: 920
    property var fixture: ({
        ok:true, state:"binding_missing", title:"Local declaration binding missing",
        detail:"Core connectivity does not prove accepted activity. Bind the existing owned declaration locally; this does not withdraw or re-declare.",
        tone:"warning", epoch:42, declarationId:"public-fixture-id", created:39, active:41,
        nonce:"0", withdrawAt:-1, mode:"Core", healthyPeers:3, bindingStatus:"missing",
        action:"repair", actionLabel:"Repair local binding",
        steps:[{label:"Online", state:"complete"}, {label:"Declared", state:"complete"}, {label:"Activated", state:"complete"}, {label:"Connected", state:"complete"}, {label:"Activity", state:"error"}, {label:"Maintaining", state:"pending"}],
        evidence:"Current-run local binding missing. Accepted activity unknown. Epoch snapshots can lag; no attributed earnings confirmed."
    })
    Loader {
        id: loader
        x: 40; y: 40
        width: harness.panelWidth
        source: harness.componentUrl
        onLoaded: { item.lifecycle = Qt.binding(function() { return harness.fixture }); item.width = Qt.binding(function() { return harness.panelWidth }) }
    }
    Connections {
        target: loader.item
        function onRepairRequested() { loader.item.resultError = false; loader.item.resultText = "Fixture only: repair clicked; no backend called." }
        function onManageRequested() { loader.item.resultText = "Fixture only: manage clicked." }
        function onRefreshRequested() { loader.item.resultText = "Fixture only: refresh clicked." }
    }
}
