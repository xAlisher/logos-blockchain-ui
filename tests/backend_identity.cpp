#include "BlendIdentity.h"
#include <QCoreApplication>
#include <QDebug>
int main(int argc,char** argv) {
 QCoreApplication app(argc,argv);
 if (BlendLifecycle::providerFromPeerId("12D3KooWMJaR5KkSibm18H2hnPCYEcHWzKorXVnswxfaHbmjuaZ7") != QString(64,'a')) return 1;
 for (const auto& invalid : {QString(), QString("not-a-peer"), QString(200,'1')})
  if (!BlendLifecycle::providerFromPeerId(invalid).isEmpty()) return 1;
 qInfo() << "PASS API public identity decoding and malformed rejection";
}
