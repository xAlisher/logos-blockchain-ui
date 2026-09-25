# Blend — source map and review notes

## Scope
90-second, silent, caption-led educational animation. Focus: block-proposal origin privacy, not a tutorial or complete protocol specification. Mesh geometry, packet count, three encryption layers and delays are illustrations, not network parameters. No live-node state appears.

## Primary sources

1. **Logos documentation — About the Blend Network**
   https://docs.logos.co/blockchain/concepts/about-the-blend-network
   Purpose, encryption, dissemination, delays, cover traffic, SDP and node roles. Direct HTTP retrieval was blocked (403); the document was recovered through search-index extraction. Current docs additionally describe Mantle transaction submissions; those are outside this introductory film’s scope.
2. **Dr. Corey Petty — Logos Blockchain in Testnet v0.2: Privacy Reaches Consensus**, 22 July 2026.
   https://blog.logos.co/article/logos-blockchain-v02
   Live article retrieved. Primary conceptual source for scenes 1–5 and 9. Distinguishes network-wide dissemination from a single visible relay path and explicitly discusses latency trade-offs.
3. **Dr. Corey Petty — Anonymous Block Proposers: How Logos Solves Leader Privacy**, 24 March 2026.
   https://blog.logos.co/article/anonymous-block-proposers
   Live article retrieved. Sources the complementary election/broadcast model, Edge’s weaker privacy, cover traffic and quota proof. Quantified anonymity multipliers and time-to-attack claims are intentionally not repeated.
4. **Implementation**, pinned to `adc72a456011795710b8bced1a21d05715f96c1d` (v0.2.4 checkout):
   https://github.com/logos-blockchain/logos-blockchain/tree/adc72a456011795710b8bced1a21d05715f96c1d
   This is a version anchor, not a claim that v0.2.4 is the latest release.

## Code cross-checks

Paths relative to that repository; inspected read-only:

- `services/blend/src/instance.rs:293–311`: Core/Edge/Broadcast enum and role selection. Below the membership-size threshold selects Broadcast; otherwise local membership selects Core; otherwise Edge. The trigger is eligible membership, not a live peer counter.
- `services/blend/src/core/processor.rs:145–155`: public-header and Proof-of-Quota verification.
- `services/blend/src/core/processor.rs:158–227`: recursive decapsulation and collected blending tokens. A node can peel multiple consecutive layers if selected repeatedly. The film illustrates layers; it does not assert that each physical node always removes exactly one.
- `services/blend/src/core/settings.rs:64–75,90–91`: scheduler cover/delay configuration and maximum release delay in rounds.
- `core/src/sdp/mod.rs:53–57,363–370`: activity value, inactivity and snapshot distinction. A declaration is not sufficient evidence of current epoch membership.
- `services/sdp/src/lib.rs:460–468`: activity submission requires declaration binding and a discoverable declaration. Generated work or local traffic is not itself chain acceptance.

## Claim-to-scene map

| Scene | Claim | Basis |
|---|---|---|
| 1–2 | Private election and network-origin protection solve different problems | Docs + both blog posts |
| 3 | Proposal gets layered encryption for selected decryptors | Docs + processor implementation |
| 4 | Encrypted copies disseminate over a peer mesh; decryption sequence is not a physical route | July blog + docs |
| 5 | Delays separate transformations; final payload proceeds to normal broadcast | Docs + July blog + scheduler settings |
| 6 | Cover resembles data; quotas constrain message origination | Docs + March blog + PoQ verifier |
| 7 | Core relays/mixes, Edge injects with less protection, small-membership fallback broadcasts | Docs + March blog + Mode::choose |
| 8 | Registration, epoch membership, service activity and acceptance are distinct | SDP and mode source |
| 9 | Traffic-analysis resistance has bandwidth/latency costs, not an absolute anonymity guarantee | Docs + July blog |

## Brand

Official **Logos Brand Guidelines v2.0, January 2026**:
https://logos.co/brand-kit/logos-brand-guidelines.pdf

Unofficial fork edition: no Logos logos or marks are rendered or distributed.
- Primary palette: `#152521`, `#F5F5EF`, `#5F797C`, `#C6EBF7`.
- Approved secondary typeface: Public Sans, regular weight 400. Font and OFL retained in `assets/`.
- Primary Rhymes typeface intentionally not used: commercial licence not established. This follows the secondary-font option, not an exact recreation of every brand typography pairing.
- Educational independent draft; not an official Logos publication.

## Reproduce

Requires Python with Pillow and edge_tts, and ffmpeg on PATH. The font is included. Logos marks are excluded from the source package.

```
python3 audio.py  # requires edge_tts; voice generation uses its online service
python3 render.py --stills
python3 render.py
ffmpeg -v error -y -ss 37.5 -i blend-explained.mp4 -frames:v 1 poster.png
python3 package.py
```

Intermediates use `/extra/tmp/blend-explainer`; final outputs are next to the script. `blend-explained.html` embeds its video, font and poster, so it works as a single offline file. `index.html` is the unpacked development player.

## Verification

- Render succeeded for all 2,160 frames; text horizontal bounds checked during generation.
- ffprobe: H.264, 1280×720, 24 fps, 90 seconds. English synthetic narration (en-US-JennyNeural), AAC audio, captions burned in. Audio and video are both exactly 90 seconds; all nine voice clips fit inside their chapters with at least 0.5 seconds of lead/tail space.
- Full ffmpeg decode completed without errors.
- Nine-scene contact sheet and an encoded-video frame visually inspected.
- Portable player: browser reports readyState 4, duration 90; chapter seek to 60.5 seconds and actual playback both succeeded.
- Mobile viewport 390 px: no horizontal overflow; video width 366 px.
- No production node/plugin changes or live transactions.

Design self-audit: educational Learn surface. No gradients, glass, invented metrics, decorative icon tiles or default Inter. The three equal columns in the roles scene are an intentional comparison, not a feature-grid landing page.
