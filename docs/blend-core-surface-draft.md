# Surfacing draft — not posted

Audience: blockchain UI maintainers. Ask: review the evidence boundaries/state mapping.

Suggested venue: the active blockchain UI coordination thread with Khushboo; precise thread not verified. Related SDP discussion: https://discord.com/channels/973324189794697286/1543871862067699732 (Youngjoon's September 8 missing-declaration investigation). Do not post automatically or mislabel this older devnet thread as the current UI thread.

Draft:

@khushboo9911 @youngjoon.lee I’m extending the fork’s node lifecycle pattern with an expandable Blend Core panel: registration, membership, connectivity and accepted activity stay separate. It complements the existing dashboard work and the missing-SDP-declaration investigation. The epic includes explicit binding recovery, without automatic withdrawal/redeclaration: https://github.com/xAlisher/logos-blockchain-ui/issues/108

Could you review the state/evidence boundaries before we consider porting it upstream? Headless verification and wild acceptance are tracked separately.
