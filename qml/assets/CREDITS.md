# Image assets

## storefront.svg

The login screen illustration, beside the form card: a shop seen from the pavement —
awning, sign board, a window with stock on the shelves, an open door, crates outside.

| | |
|---|---|
| Origin | **Original work for this project.** No third party, no licence to carry |
| viewBox | 784 x 566 (landscape, cropped to the drawing) |
| Palette | `Tokens` hues only: emerald `#3ECF7A`, sign `#24304E`, greys `#EFF4FA`–`#8A93A6`, produce in amber/rose/teal |

### Why it is drawn and not borrowed

The two illustrations before it were about *paying* — a stock drawing of a card being
tapped (unDraw's "Mobile payments"), and before that a blurred photograph of a market
street. Both were pictures of a transaction or of a mood. The people who log into this
program are standing behind a counter in a shop, and a picture of that shop is the only
one that says whose till this is before a word is read. Nothing off the shelf said it,
so it is drawn here.

Being original also settles the question the previous file needed a licence table to
answer, and it is 6KB instead of 37KB.

### Constraints it is drawn under

**The colours are baked in on purpose.** QML cannot tint an SVG's internals — an
`Image` renders whatever colours the file carries — so unlike `pos`, which recolours
its artwork from the active theme at load time, pos2 has to ship the colours it wants.

It sits on the login gradient (`Tokens.loginFrom` `#0C4A4E` → `Tokens.loginTo`
`#05090F`), which is why:

- the large shapes are near-white and the darkest ink is the sign board `#24304E`;
  anything closer to black vanishes into the bottom of the gradient;
- the awning's pale stripes are blue-grey `#DCE6F2`, not white — against a near-white
  facade a white stripe is not a stripe;
- one soft emerald wash sits behind the building so it is not a bright block dropped
  onto a dark backdrop.

**No text.** The sign board carries three rounded bars instead of a shop name: a baked-in
word would be one language on a screen that offers three, and a font that may not be
installed. The bars read as "the name goes here" everywhere.

**No arc flags.** The scalloped awning edge is full circles drawn behind each stripe in
the stripe's own colour. Arcs with the wrong sweep flag are the classic way an SVG
renders inside out somewhere else, and this file has to survive Qt's SVG support rather
than a browser's.

### Replacing it

Drop a different SVG in at this name. Aim for a landscape-ish viewBox and light values.
If the file is missing the screen keeps the gradient and loses only the picture
(`LoginPage.qml` guards on `Image.Ready`).

---

## pos-terminal.svg — REMOVED

unDraw's "Mobile payments" by Katerina Limpitsouni (undraw.co), vendored from the
MIT-licensed mirror <https://github.com/cuuupid/undraw-illustrations>
(`svg/mobile_payments_edgf.svg`) and recoloured from its indigo to the brand emerald.
Its licence asked for no attribution; the credit was recorded anyway.

Removed rather than left unreferenced: it drew a phone being tapped on a reader, which
is a picture of a payment method this program does not have, in a country where a corner
shop takes cash. `storefront.svg` replaced it. Recorded here so the deletion is not
mistaken for a lost file.

---

## login-bg.jpg — REMOVED

A blurred CC0 photograph (an evening market in Hong Kong, by Annie Spratt, from
<https://commons.wikimedia.org/wiki/File:Evening_market_in_Hong_Kong.jpg>) used to
fill the whole login window. It was removed, not just unreferenced: a soft-focus
street is atmosphere, and it never said what the program is. The reasoning is in
`LoginPage.qml`'s header. Recorded here so the deletion is not mistaken for a lost
file.
