# Bunni look (from the "RecallBnuy Look" design canvas)

`Main.dc.html` is the design (HTML/CSS + JS). The PNGs are renders of it with neya's
chosen settings (dark mode). Build these into the Swift app. Light mode uses the same
rules with the light colours below. Missing pictures in the renders are just local
render gaps (Josh photo, Discord art); use the app's real images.

## Chosen settings (prop defaults in Main.dc.html)
theme Pastel · logo Pink · lockup Tucked · play button Blue · app accent = Bunni accent ·
accent Pink · tag "E Bunny ears" · font Fredoka (bold 700) · outline Double · letter shade Cel ·
ears "Swaps sides" · fidget Wild · window title "Recall (Bunni)" · about "A One line" ·
What's New "A Raised and sunk" · your heading "From bunni" · Recall icons Grey ·
patch glow Soft · What's different "In About" · Josh card Compact · invite Recall's server ·
tiles Pink icons · changed Both.

## Colours
Pink accent: bn #c2185b (light) / #ff8fb8 (dark); bnTag #d81b6a; bnMid #ff5c93.
App accent (`--ac`, used where Recall uses orange) = bnMid #ff5c93.
Pastel light: ground #fff0f6, surface #fffafd, ink #4b1d38, sec #97607e, hair rgba(214,80,140,.14), well rgba(214,80,140,.08), bnSoft #ffe0ec, glow rgba(255,120,175,.22).
Pastel dark: ground #1b1120, surface #2a1a2f, ink #ffeef5, sec #cda6bb, hair rgba(255,150,195,.13), well rgba(0,0,0,.3), bnSoft #47213a, glow rgba(255,92,147,.13).
Discord card in pastel: see `.app.thPastel` / `.app.dark.thPastel` (dFrame, dEdge, dEmbed, dHead, dBtn…).

## Screens
- **Home** (home.png): pink app icon (logo-pink.png), "Recall" wordmark with the BUNNI
  sticker tucked under it and bunny ears on the sticker (SVG in the design, class `stk`, tag E).
  Pastel background glow. Josh card is the compact one line "Recall is made by Josh." + the
  two pill buttons (keep them inside the card; the render overflows a bit, fix that).
  Status line: "Version 1.6.7-bunni" is clickable → opens What's New; "· Up to date ·";
  "What's different" link (pink) → opens About. Tile icons pink.
- **About** (about.png): pink icon follows the logo. Credit line "A One line" style
  (Bunni by neya, on top of Recall by Josh). Split GitHub button: one segmented pill,
  left half "Asher" (black, opens github.com/AsherJN/recall), right half "Bunni"
  (pink, opens github.com/ayyneya/recall-bnuy). "What's different in Bunni" card with
  soft static glow and collapsible rows with a chevron: "Discord" (Your Discord card,
  Share codes) open by default, "Bunni look" closed.
- **What's New** (whats-new.png): "From bunni" panel first (raised, soft static pink glow,
  pink icons), then Recall's items (sunk, grey icons).
- **Update prompt** (update.png): shows the new Bunni version and a pink line
  "From Bunni's GitHub, signed with Bunni's certificate".

## Animation rules (neya cares a lot)
- Ears: one ear floppy; it swaps sides now and then (every ~5–14 s on Wild), starting on a
  random side. Small fidgets in between. See earPose/earBlend/stepEars in the JS.
- ALL animation must stop completely when the window is not key, is hidden, or the app is
  in the background (no timers, no CVDisplayLink, no layer animations running). It must never
  cost frames while Overwatch is running. Resume when the window is focused again.
- Patch-notes glow is static (no moving glow).
