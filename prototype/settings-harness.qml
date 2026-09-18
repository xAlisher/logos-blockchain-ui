import QtQuick
import QtQuick.Window
import Logos.Theme
import "../src/qml/views" as V
Window {
    id: win; width: 900; height: 980; visible: true; color: Theme.palette.background
    V.SettingsView { anchors.fill: parent }
    Timer { interval: 1400; running: true; onTriggered: { win.contentItem.grabToImage(function(r){ r.saveToFile("settings.png"); Qt.callLater(Qt.quit) }) } }
}
