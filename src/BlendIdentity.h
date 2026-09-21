#pragma once
#include <QByteArray>
#include <QString>

namespace BlendLifecycle {
// libp2p Ed25519 inline PeerId: identity multihash of PublicKey protobuf.
// Unsupported key formats deliberately return unknown rather than guessing.
inline QString providerFromPeerId(const QString& peer)
{
    if (peer.isEmpty() || peer.size() > 128) return {};
    const QByteArray alphabet("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz");
    QByteArray number(1, '\0');
    for (const QChar character : peer) {
        int carry = alphabet.indexOf(character.toLatin1());
        if (carry < 0) return {};
        for (int index = number.size() - 1; index >= 0; --index) {
            carry += static_cast<unsigned char>(number[index]) * 58;
            number[index] = char(carry & 255);
            carry >>= 8;
        }
        while (carry) { number.prepend(char(carry & 255)); carry >>= 8; }
    }
    int leading = 0;
    while (leading < peer.size() && peer[leading] == QLatin1Char('1')) ++leading;
    number.prepend(QByteArray(leading, '\0'));
    if (number.size() != 38 || !number.startsWith(QByteArray::fromHex("002408011220"))) return {};
    return QString::fromLatin1(number.mid(6).toHex());
}
}
