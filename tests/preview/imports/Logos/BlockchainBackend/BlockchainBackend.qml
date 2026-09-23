pragma Singleton
import QtQuick
QtObject {
    enum BlockchainStatus { NotStarted=0, Starting=1, Running=2, Stopping=3, Stopped=4, Error=5 }
    enum BlendStatus { Off=0, WaitingForOnline=1, Edge=2, Core=3, Broadcast=4, NodeError=5, BlendError=6, Unknown=7, Activating=8, CoreDeclaredEdge=9 }
}
