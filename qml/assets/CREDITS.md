# Image assets

## login-bg.jpg

The login screen background.

| | |
|---|---|
| Title | Evening market in Hong Kong |
| Photographer | Annie Spratt |
| Licence | **CC0 1.0 — Public Domain Dedication** (<http://creativecommons.org/publicdomain/zero/1.0/>) |
| Taken | 2017-05-17 |
| Source | <https://commons.wikimedia.org/wiki/File:Evening_market_in_Hong_Kong.jpg> |
| Originally | <https://unsplash.com/photos/5VVpEHPv1yo> |

CC0 waives every right the photographer had, so this needs no attribution and
imposes no share-alike condition on the product. The credit above is recorded
anyway, because "where did this file come from" is a question somebody will ask
later and a licence nobody can trace is a licence nobody can rely on.

### What was done to it

Downloaded at 1920px wide, then, with Pillow:

- `GaussianBlur(radius=5)`
- `ImageEnhance.Color(0.92)` — slightly desaturated
- JPEG quality 80, progressive, optimised → 1920x1278, 178 KB

**The blur is baked into the file on purpose.** It is not a stylistic whim: this
build has no blur available at run time. `QtQuick.Effects` (`MultiEffect`) is not
verified present — LoginPage's own header has said so since the port — and a
sharp photograph of a signage-covered street directly behind a login form makes
both the form and the photograph harder to read. Baking it also cut the file from
924 KB to 178 KB.

The darkening is *not* baked in. That is a scrim in LoginPage.qml, so it can be
retuned for a theme without re-encoding the photograph.

### Replacing it

Drop a different JPEG in at this name and nothing else has to change. Aim for
about 1920px wide, landscape, and something with a calm centre — the login card
sits in the middle of it. If the file is missing entirely the screen falls back to
the plain `Tokens.loginFrom` -> `Tokens.loginTo` gradient it used before, so a
broken path costs the photograph and nothing else.
