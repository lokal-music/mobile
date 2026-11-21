# Desktop link and appearance polish

Specification: the supplied Phase 4/5 handoff and current main. The older referenced design-flow document was unavailable. Existing native audio, USB and DSD paths are retained.

## Desktop link

In Lokal desktop, enable Phone Remote and choose Pair a phone in Linked devices. In Konnekted2 use You → Devices, settings, or the optional onboarding step. Scan the QR code or enter the desktop address and two-minute code on the same LAN. Discovery uses Android NSD, with a manual-address fallback and local-network permission on Android versions that require it.

Connecting does not enable library merge. Review the merge preview first. Enabling merge combines existing likes, local playlists and listening history without deleting files or inferring deletions from missing rows. The journal uses stable IDs and clocks; imported events do not scrobble again. Desktop-only songs show their availability and can be downloaded from song actions. Files cached for streaming remain subject to the existing cache cap; explicit downloads are durable local copies.

Choose desktop output to drive the existing player controls and media notification. The output pill opens device settings. Play on phone / Play on desktop prepares destination tracks before fading the source. The desktop's Devices panel also controls the phone. Download sharing is off by default: enabling it queues completed phone downloads for copying to that desktop and permits copying missing handoff songs. Original files remain in place. Theme sync is independently opt-in.

While paired and connected, a song's long-press menu can send a locally available phone file to the desktop. Desktop-initiated copies send `command` action `copyTracksToPhone` with `value: { "tracks": ["<desktop-track-id>"] }`; the phone resolves only those IDs with authenticated `POST /api/remote/library/tracks/lookup` (`{ "ids": [...] }` → `{ "items": [...] }`) and saves originals into the existing selected music folder. Incoming batches accept 1–100 unique IDs, copy sequentially while Lokal is foregrounded, skip originals already on the phone, and report unavailable or failed items in the acknowledgement and the desktop-link status. Android still requires access to the selected music folder; iOS copies remain subject to its foreground transfer limits. These copies do not run as background jobs.

## Appearance and languages

Accent changes propagate through existing launcher aliases, media notifications (including radio), and widgets that follow the app theme. Explicit widget colors remain overrides. Performance advice samples foreground glass rendering against the display's frame budget and can offer a once-only performance-mode action; it never enables the mode automatically.

The language picker includes English, French, German, Spanish, Italian, Brazilian Portuguese, Dutch, Polish and Swedish, and retains Simplified Chinese. Generated localization resources and fixed Lokal UI phrases are translated; track metadata, brands, language autonyms and route identifiers are preserved. Added translations include machine-generated text and need native-speaker review.

## Implementation status

Changes span this repository and the companion `CHEYCKIT/lokal` desktop checkout. See its `docs/desktop-link.md` for the wire protocol and desktop persistence. No CI, tests, analysis or builds were run for these feature changes at the user's request. Physical discovery, handoff, Android background playback, camera permission, launcher and widget behavior remain unverified. No hardware playback claims are made.

## Follow-up interface fixes

The Library header uses the same 20/12/16/0 padding, 44-pixel buttons and 24-pixel icons as Home and You. The footer now follows the first user scroll delta, including direction reversals and overscroll; horizontal shelves do not change its mode.

The mini-player cover and player sheet follow one progress value during tap, drag, settle and close. A released pull settles before transferring the existing player state into the route, retaining decoded covers and backdrop phase. Covers share a clip around both images during replacement; neighbouring covers are decoded in the carousel before entry. Transport buttons use the cover carousel, metadata dissolves between tracks, and album names are omitted from the full player.

The full-player backdrop now moves the actual artwork on an eased, reversing 18-second motion. Track changes retain the motion phase and dissolve decoded images instead of resetting a non-periodic palette animation.

Share cards use one fixed 360×450 canvas for preview and 1080×1350 PNG export, with current Konnekted branding and self-contained image filtering. Template selection, editable lyric text, gallery save and native sharing all use the selected canvas. Artwork decoding finishes before export; a busy export freezes template controls. Filenames do not include unsanitized song IDs. Old backdrop sampling and Flick watermarks have been removed from card templates.

These follow-up changes were source-reviewed and formatted only; no builds, analysis, tests, simulator or physical-device checks were run, as requested. The visual result still needs device review.
