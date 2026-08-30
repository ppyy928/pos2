"""Vendor FluentPySide into pos2 and scale every size up to touch density.

Why this exists
---------------
FluentPySide is authored at Windows-desktop density: 32px controls, 14px body
text, 16px icons. MIZAN POS is operated on a counter, often with a finger, by
merchants whose feedback was literally "make it bigger". Scaling has to happen
inside the library because the sizes are baked into a 20k-line Figma export
(``Config.qml``) that every styled control reads at runtime — no public knob
exists.

This is a *transformer*, not a one-off edit: it reads a pristine FluentPySide
package and writes a scaled copy. Re-run it after upgrading FluentPySide and the
scaling survives. Every change is logged to ``SCALE_REPORT.md`` for review.

Output layout, and why it is not a plain copytree
-------------------------------------------------
``_installer.default_style_path()`` returns ``<pkg>/QtQuick/Controls/FluentWinUI3``,
but the source ships the style at ``<pkg>/fluent_winui3``. In the pristine tree
that path does not exist, so ``apply()`` silently falls back to the style
installed inside PySide6 — and a scaled ``fluent_winui3/Config.qml`` would have
had *zero* effect. The vendored copy therefore relocates the style to the path
the installer actually looks for::

    vendor/fluentpyside/
        __init__.py, _loader.py, ...            verbatim
        QtQuick/Controls/FluentWinUI3/          <- from fluent_winui3/, scaled
        FluentControls/                         <- scaled

``pos2/vendor`` goes on ``sys.path``, so ``import fluentpyside`` resolves to this
copy and the style path resolves without patching anything upstream.

The ``prefer`` line
-------------------
Both style ``qmldir`` files carry::

    prefer :/qt-project.org/imports/QtQuick/Controls/FluentWinUI3/

which redirects *every* QML file load into the resources compiled into the style
DLL. While that line is present, on-disk edits are dead code. Stripping it from
the vendored copy is the documented way to customise a built-in Qt style; the
``plugin`` line stays so the C++ types still register.

Five layers get scaled
----------------------
1. ``QtQuick/Controls/FluentWinUI3/Config.qml`` — the Figma export. 12,204
   numeric properties, of which 6,652 are geometry/type and 5,552 must NOT be
   touched (sprite-atlas coords and ``Qt.Align*`` enum flags).
2. **Both** ``Fluent.qml`` token singletons — the style has its own, read by the
   52 styled standard controls, and ``FluentControls`` has another, read by the
   47 custom controls. Scaling only one leaves half the library at desktop
   density.
3. ``*.qml`` in both modules — hardcoded literals in the controls themselves.
4. ``qmldir`` — the ``prefer`` redirect, removed.
5. A short, explicit patch table for sizes that are *unreachable* by layer 3.

Why layer 5 has to exist
------------------------
Layer 3 only rewrites a numeric literal that is the entire right-hand side of an
assignment. That restriction is what makes it safe — it cannot corrupt
``duration: Fluent.anim.speed`` or ``width: parent.width - 8``. The cost is that
FluentPySide writes some of its most important sizes *inside* expressions::

    implicitHeight: isMacStyle ? 12 : 40          // caption button
    implicitWidth: Math.max(320, Math.min(..., 600))   // dialog

Those are invisible to layer 3, and the result is not merely "less scaled" — it
is *broken*, because siblings that were the same size no longer are. The caption
buttons are the clearest case: ``windowTitleBarHeight`` scales 48 -> 56 in layer
2, the buttons stay 40, they sit in a ``Row`` (which does not stretch its
children), and the visible result is a 16px gap under Close. So each entry below
restores a relationship the generic layers would otherwise break. Every patch
must match exactly the number of times it says it will; a miss is reported and
exits non-zero rather than passing silently.

Usage
-----
    python tools/scale_fluent.py                     # default paths
    python tools/scale_fluent.py --check             # report only, no writes
    python tools/scale_fluent.py --geom 1.6          # override geometry scale
"""

from __future__ import annotations

import argparse
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

# Where the source ships the style, and where the installer expects to find it.
SRC_STYLE_DIR = "fluent_winui3"
DST_STYLE_DIR = Path("QtQuick") / "Controls" / "FluentWinUI3"
CONTROLS_DIR = "FluentControls"

# --------------------------------------------------------------------------
# Scale policy
# --------------------------------------------------------------------------

# Geometry multiplier. 1.5 turns Fluent's 32px control into 48px — exactly the
# touch floor MIZAN already mandates (pos tokens: touch_target=48), and its
# 40px list row into 60px. Applied to heights, widths, paddings, spacing and
# corner offsets.
GEOM_SCALE = 1.5

# Values below this stay untouched: 0 and 1 are hairlines, separators and
# border widths. Scaling them produces blurry 1.5px lines and fat dividers.
GEOM_MIN = 2.0

# Type scale is deliberately gentler than geometry (~1.2x, not 1.5x). Body text
# at 14*1.5 = 21px would be comical; 17px is readable at arm's length and is
# what MIZAN's own "large" font preset already uses. More padding relative to
# text IS what touch density means.
FONT_MAP: dict[int, int] = {
    8: 11,
    9: 12,
    10: 13,
    11: 14,
    12: 15,
    13: 16,
    14: 17,   # body — the one that matters most
    15: 18,
    16: 19,
    17: 20,
    18: 21,
    20: 24,
    22: 26,
    24: 28,
    28: 32,
    32: 36,
    36: 40,
    40: 44,
    48: 52,
    68: 72,
}

# Config.qml property names that represent size and must scale.
SCALE_PROPS: frozenset[str] = frozenset({
    "height", "width",
    "spacing",
    "topPadding", "bottomPadding", "leftPadding", "rightPadding",
    "topOffset", "bottomOffset", "leftOffset", "rightOffset",
})

# Config.qml property names that must NOT scale, with the reason.
#   x, y                        Figma sprite-atlas coordinates, not layout
#   textHAlignment/VAlignment   Qt.Align* enum FLAGS (4, 128, ...) — scaling
#                               them silently corrupts alignment
#   *Shadow                     shadow metadata, unused by the QML
FROZEN_PROPS: frozenset[str] = frozenset({
    "x", "y",
    "textHAlignment", "textVAlignment",
    "topShadow", "bottomShadow", "leftShadow", "rightShadow",
})

FONT_PROPS: frozenset[str] = frozenset({"fontSize"})

# Layer-3 whitelist: property names inside control QML that are safe to scale
# when assigned a bare numeric literal.
CONTROL_GEOM_PROPS: frozenset[str] = frozenset({
    "height", "width",
    "implicitHeight", "implicitWidth",
    "minimumHeight", "minimumWidth", "maximumHeight", "maximumWidth",
    "preferredHeight", "preferredWidth",
    "cellHeight", "cellWidth",
    "radius",
    "spacing", "columnSpacing", "rowSpacing",
    "padding", "topPadding", "bottomPadding", "leftPadding", "rightPadding",
    "margins", "topMargin", "bottomMargin", "leftMargin", "rightMargin",
    "size", "iconSize",
    "navExpandWidth", "navCompactWidth",
    "handleSize", "indicatorHeight", "indicatorWidth",
})

CONTROL_FONT_PROPS: frozenset[str] = frozenset({"pixelSize", "fontSize"})

# `border.width` is a hairline, never scaled, regardless of the name whitelist.
CONTROL_FROZEN_PREFIXED: frozenset[str] = frozenset({"border.width"})

# Layer-2 explicit token table. Left = pristine value, right = scaled value.
# Hand-picked rather than multiplied because each of these has a design intent
# that a blanket multiplier would fumble. Applied to BOTH Fluent.qml singletons,
# which carry an identical token block.
FLUENT_QML_TOKENS: dict[str, tuple[str, str, str]] = {
    # property                  type      old     new
    "buttonRadius":            ("int",   "5",    "8"),
    "smallRadius":             ("int",   "3",    "5"),
    "dialogTitleBarHeight":    ("int",   "32",   "48"),
    "windowTitleBarHeight":    ("int",   "48",   "56"),   # == MIZAN top_bar
    "windowRadius":            ("int",   "7",    "10"),
    "windowButtonWidth":       ("int",   "46",   "56"),
    "scrollBarMinWidth":       ("int",   "2",    "4"),
    "scrollBarWidth":          ("int",   "6",    "12"),   # finger-draggable
    "scrollBarPadding":        ("int",   "3",    "5"),
    "sliderHandleSize":        ("int",   "20",   "28"),
    "display":                 ("int",   "68",   "72"),
    "titleLarge":              ("int",   "40",   "44"),
    "title":                   ("int",   "28",   "32"),
    "subtitle":                ("int",   "20",   "24"),
    "bodyLarge":               ("int",   "18",   "21"),
    "body":                    ("int",   "14",   "17"),
    "bodyStrong":              ("int",   "14",   "17"),
    "caption":                 ("int",   "12",   "15"),
    "xxs":                     ("real",  "2",    "4"),
    "xs":                      ("real",  "4",    "6"),
    "s":                       ("real",  "8",    "12"),
    "m":                       ("real",  "12",   "16"),
    "l":                       ("real",  "16",   "20"),
    "xl":                      ("real",  "20",   "24"),
    "xxl":                     ("real",  "24",   "32"),
    "small":                   ("real",  "4",    "6"),
    "medium":                  ("real",  "8",    "10"),
    "large":                   ("real",  "12",   "14"),
    "xlarge":                  ("real",  "16",   "18"),
    "windowDragArea":          ("int",   "8",    "10"),
    # deliberately untouched: borderWidth (hairline), circle (sentinel 9999),
    # borderFactor / borderOnAccentFactor (ratios), every anim duration.
}

# Layer-4: qmldir directives dropped from the vendored style modules.
# `prefer` is the one that matters — see the module docstring. The rest are
# build-system metadata that only makes sense inside Qt's own build tree.
QMLDIR_DROP_PREFIXES: tuple[str, ...] = ("prefer ", "linktarget ")


# --------------------------------------------------------------------------
# Layer 5 — targeted patches
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Patch:
    """One substitution the generic layers provably cannot make.

    ``find`` is matched as exact text, not a regex, so what is written here is
    what is in the file. ``expect`` is the number of occurrences required: it
    turns an upstream rename into a loud failure instead of a silent no-op.
    """

    file: str          # module-relative path, as layer 3 names it
    find: str
    replace: str
    why: str
    expect: int = 1


# The horizontal ScrollBar's track, verbatim, for the patch below. Kept as one
# string so the replacement is derived from it rather than retyped: every line
# here has to match the layer-3 output exactly, and two hand-written copies of
# 29 lines is one transposed space away from a patch that silently does nothing.
H_TRACK = """        background: Rectangle{
            id: background
            radius: 8
            color: Fluent.scrollBarTrackColor
            opacity: 0
            visible: horizontalScrollBar.size < 1.0

            states: [
                State{ name: "show"; when: contentItem.collapsed; PropertyChanges { target: background; opacity: 1 } },
                State{ name: "hide"; when: !contentItem.collapsed; PropertyChanges { target: background; opacity: 0 } }
            ]

            transitions:[
                Transition {
                    to: "hide"
                    SequentialAnimation {
                        PauseAnimation { duration: 450 }
                        NumberAnimation { target: background; properties: "opacity"; duration: 167; easing.type: Easing.OutCubic }
                    }
                },
                Transition {
                    to: "show"
                    SequentialAnimation {
                        PauseAnimation { duration: 150 }
                        NumberAnimation { target: background; properties: "opacity"; duration: 167; easing.type: Easing.OutCubic }
                    }
                }
            ]"""


TAIL_FIND = 'if (modelData > 0) selectedDate = new Date(currentYear, currentMonth, modelData)\n                        }\n                    }\n                }\n            }\n        }\n    }\n}\n'

TAIL_REPLACE = 'if (modelData > 0) selectedDate = new Date(currentYear, currentMonth, modelData)\n                        }\n                    }\n                }\n            }\n        }\n    }\n}\n}\n'

PATCHES: tuple[Patch, ...] = (
    # -- the calendar ------------------------------------------------------
    # CalendarView does not parse and could not have: its root Rectangle is never
    # closed, so the file ends one brace short. Like ScrollView, nobody upstream
    # noticed because the resource redirect means the compiled-in copy is the one
    # Qt loads — and layer 4 strips that redirect.
    Patch(
        file="FluentControls/CalendarView.qml",
        find=TAIL_FIND,
        replace=TAIL_REPLACE,
        why="CalendarView: the root Rectangle is never closed, so the file does not parse",
    ),
    # And its day grid assigns `model`, which GridLayout does not have. It is meant
    # to be the view's own list of day numbers — the Repeater below reads
    # `dayGrid.model` — so it has to be declared rather than assigned.
    Patch(
        file="FluentControls/CalendarView.qml",
        find="            model: {\n                var first = new Date(currentYear, currentMonth, 1)",
        replace="            property var model: {\n                var first = new Date(currentYear, currentMonth, 1)",
        why="CalendarView: GridLayout has no `model` property; the day list has to be declared",
    ),
    # -- ScrollView: two ScrollBars, one document, four shared ids ---------
    # Not a scaling fix. FluentPySide's own ScrollView declares its vertical and
    # horizontal ScrollBars in the same QML document and gives the thumb `id:
    # bar` and the track `id: background` in BOTH — ids are unique per document,
    # so the file does not parse and `QC.ScrollView` is simply unavailable. The
    # author clearly meant to keep them apart: the enclosing Item is `item` in one
    # block and `itemH` in the other. This finishes that rename for the
    # horizontal block.
    #
    # It matters here because the resource redirect is stripped (layer 4): with
    # `prefer` in place Qt loads the style's compiled-in resources and never
    # parses this file, which is why the bug survives upstream. The first thing
    # in this app to import a ScrollView — the nav rail — takes the whole window
    # down with it.
    Patch(
        file="QtQuick/Controls/FluentWinUI3/ScrollView.qml",
        find=(
            "                id: bar\n"
            "                width:  horizontal ? horizontalScrollBar.minimumWidth"
        ),
        replace=(
            "                id: barH\n"
            "                width:  horizontal ? horizontalScrollBar.minimumWidth"
        ),
        why="horizontal thumb: id bar -> barH (duplicate id, file does not parse)",
    ),
    Patch(
        file="QtQuick/Controls/FluentWinUI3/ScrollView.qml",
        find=(
            "PropertyChanges { target: bar; width:  horizontal ? "
            "horizontalScrollBar.expandWidth : parent.width; height: horizontal ? "
            "horizontalScrollBar.expandWidth : parent.height }"
        ),
        replace=(
            "PropertyChanges { target: barH; width:  horizontal ? "
            "horizontalScrollBar.expandWidth : parent.width; height: horizontal ? "
            "horizontalScrollBar.expandWidth : parent.height }"
        ),
        why="the expanded state of that thumb follows the rename",
    ),
    Patch(
        file="QtQuick/Controls/FluentWinUI3/ScrollView.qml",
        find=(
            "PropertyChanges { target: bar; width:  horizontal ? "
            "horizontalScrollBar.minimumWidth : parent.width; height: horizontal ? "
            "horizontalScrollBar.minimumWidth : parent.height }"
        ),
        replace=(
            "PropertyChanges { target: barH; width:  horizontal ? "
            "horizontalScrollBar.minimumWidth : parent.width; height: horizontal ? "
            "horizontalScrollBar.minimumWidth : parent.height }"
        ),
        why="and its collapsed state",
    ),
    # Both transitions in the horizontal block, and only those: the vertical
    # pair spells the same line with `vertical ?`.
    Patch(
        file="QtQuick/Controls/FluentWinUI3/ScrollView.qml",
        find=(
            "NumberAnimation { target: bar; properties: horizontal ? "
            '"width"  : "height"; duration: 167; easing.type: Easing.OutCubic }'
        ),
        replace=(
            "NumberAnimation { target: barH; properties: horizontal ? "
            '"width"  : "height"; duration: 167; easing.type: Easing.OutCubic }'
        ),
        why="both transitions that animate it",
        expect=2,
    ),
    # The track is patched as one block rather than as four substitutions: its
    # states and transitions are textually identical in the two ScrollBars, so a
    # narrower patch would rename the declaration and leave the references
    # pointing at the *vertical* track — a silent behaviour bug instead of a loud
    # parse error, which is the worse of the two.
    Patch(
        file="QtQuick/Controls/FluentWinUI3/ScrollView.qml",
        find=H_TRACK,
        replace=(
            H_TRACK.replace("id: background", "id: backgroundH")
            .replace("target: background", "target: backgroundH")
        ),
        why="horizontal track: id background -> backgroundH, references included",
    ),
    # The same file's four scroll arrows assign `size` and `color`, which the
    # style's ToolButton does not have — another consequence of nobody ever
    # parsing this file. `icon.width/height` and `icon.color` are the properties
    # that were meant, and 8 -> 12 is the geometry scale, so the arrows end up
    # sized the way every other glyph in the vendored copy is.
    Patch(
        file="QtQuick/Controls/FluentWinUI3/ScrollView.qml",
        find=(
            "            width: 15; height: 15; size: 8\n"
            "            color: Fluent.textSecondary"
        ),
        replace=(
            "            width: 15; height: 15\n"
            "            icon.width: 12; icon.height: 12\n"
            "            icon.color: Fluent.textSecondary"
        ),
        why="scroll arrows: size/color -> icon.width/height/icon.color",
        expect=4,
    ),
    # -- toasts ----------------------------------------------------------
    # `height: mainLayout.height + 20` on a layout that fills the toast: the
    # toast's height defines the layout's, so the layout's cannot define the
    # toast's. Qt breaks the loop by leaving one of them at a stale value, which
    # is why a two-line toast can come out clipped. implicitHeight is the content
    # height and depends on nothing above it; the padding then comes from the
    # margins the layout already uses instead of a number that predates them.
    Patch(
        file="FluentControls/Toast.qml",
        find="height: mainLayout.height + 20",
        replace="height: mainLayout.implicitHeight + 2 * mainLayout.anchors.margins",
        why="toast height: binding loop against its own filled layout",
    ),
    # -- window caption buttons ------------------------------------------
    # Only ever used by TitleBar (checked), so a constant is safe here and a
    # binding to parent.height — which would loop against Row.implicitHeight —
    # is not. 56 is the scaled windowTitleBarHeight, so the buttons span the bar
    # exactly, which is both what Windows does natively and a 56x56 target.
    Patch(
        file="FluentControls/CtrlBtn.qml",
        find="implicitHeight: isMacStyle ? 12 : 40",
        replace="implicitHeight: isMacStyle ? 12 : 56",
        why="fill the scaled 56px title bar instead of leaving a 16px gap",
    ),
    Patch(
        file="FluentControls/CtrlBtn.qml",
        find="implicitWidth: isMacStyle ? 12 : 46",
        replace="implicitWidth: isMacStyle ? 12 : 56",
        why="square caption buttons, matching windowButtonWidth 46 -> 56",
    ),
    # The glyphs are the smallest thing in the window chrome and the mac
    # variants are 12px circles, so only the Windows sizes move.
    Patch(
        file="FluentControls/CtrlBtn.qml",
        find="size: mode === 0 ? 14 : 16",
        replace="size: mode === 0 ? 17 : 19",
        why="caption glyphs, through the same type map as everything else",
    ),
    # -- dialogs ---------------------------------------------------------
    # Both bounds move together: scaling only the minimum would let a dialog
    # hit its cap at 600px with 17px text inside, which wraps text that used to
    # fit on one line.
    Patch(
        file="FluentControls/FluentDialog.qml",
        find=(
            "implicitWidth: Math.max(320, Math.min(implicitContentWidth "
            "+ leftPadding + rightPadding, 600))"
        ),
        replace=(
            "implicitWidth: Math.max(480, Math.min(implicitContentWidth "
            "+ leftPadding + rightPadding, 900))"
        ),
        why="dialog width bounds 320..600 -> 480..900 for 17px body text",
    ),
    # -- suggestion popups ----------------------------------------------
    # 200px held 5 rows at 40px. At 60px rows it holds 3, which turns a
    # scan-and-pick into a scroll. Both occurrences are the same cap: one on the
    # popup, one on the list inside it.
    Patch(
        file="FluentControls/AutoSuggestBox.qml",
        find="Math.min(suggestList.contentHeight, 200)",
        replace="Math.min(suggestList.contentHeight, 320)",
        why="popup height cap: keep ~5 visible rows at the scaled row height",
    ),
    Patch(
        file="FluentControls/AutoSuggestBox.qml",
        find="Math.min(contentHeight, 200)",
        replace="Math.min(contentHeight, 320)",
        why="the same cap on the inner list",
    ),
    # -- selection indicator --------------------------------------------
    # A 3px bar beside 60px rows reads as a rendering artefact. 4px is still
    # restrained and survives fractional DPI.
    Patch(
        file="FluentControls/Indicator.qml",
        find="implicitWidth: orientation === Qt.Horizontal ? 16 : 3",
        replace="implicitWidth: orientation === Qt.Horizontal ? 24 : 4",
        why="selection bar: 3 -> 4 thick, 16 -> 24 long",
    ),
    Patch(
        file="FluentControls/Indicator.qml",
        find="implicitHeight: orientation === Qt.Horizontal ? 3 : currentItemHeight - 23",
        replace="implicitHeight: orientation === Qt.Horizontal ? 4 : currentItemHeight - 34",
        why="same thickness, and the row inset scales with the row (23 -> 34)",
    ),
)

# Sizes that look scalable and are not, kept here so the reasoning is recorded
# rather than rediscovered:
#   NavigationBar.minimumExpandWidth: 900   a window-width BREAKPOINT, not a
#       size. Scaling it to 1350 would collapse the rail on almost every till.
#       Safe today only because the name is absent from CONTROL_GEOM_PROPS.
#   fluent_winui3/rini/*.qml                an unreferenced copy of
#       NavigationView/NavigationBar with Chinese comments; absent from the
#       style qmldir, so it cannot be imported as a module and is left
#       byte-identical and unscaled.


def apply_patches(rel: str, text: str, report: Report) -> str:
    """Apply every patch registered against ``rel``, verifying each one."""
    for patch in PATCHES:
        if patch.file != rel:
            continue
        found = text.count(patch.find)
        if found != patch.expect:
            report.patches_missed.append(
                f"`{rel}` — expected {patch.expect} x `{patch.find}`, "
                f"found {found} ({patch.why})"
            )
            continue
        text = text.replace(patch.find, patch.replace)
        report.patches_applied.append(f"`{rel}` — {patch.why}")
    return text


# --------------------------------------------------------------------------
# Layer 6 — runtime compatibility
# --------------------------------------------------------------------------
# Not scaling, and not aimed at one file: FluentPySide ships style files written
# against a Qt newer than what this project declares (PySide6>=6.6, running
# 6.9.3), so a handful of expressions read APIs the runtime does not have. With
# the resource redirect in place these files are never parsed and nobody
# notices; layer 4 strips that redirect, which is what puts them in front of the
# engine — so the incompatibility is this tool's to carry.
#
# Applied to every QML file, with no expected count: these are the *absence* of
# an API, so a version of FluentPySide that has stopped using it should make the
# substitution disappear quietly rather than fail the build.

COMPAT: tuple[tuple[str, str, str], ...] = (
    (
        "Application.styleHints.accessibility.contrastPreference",
        "(Application.styleHints.accessibility "
        "? Application.styleHints.accessibility.contrastPreference : 0)",
        "QStyleHints.accessibility arrived after Qt 6.9: every control that "
        "asks for the high-contrast preference throws a TypeError per instance, "
        "which is a flooded console and a style that never resolves its "
        "high-contrast colours. 0 is Qt.NoPreference, so the ordinary branch is "
        "taken when the API is missing — and `Qt.HighContrast` being undefined "
        "on such a runtime is exactly why the comparison cannot be left to "
        "resolve itself",
    ),
    # Not a version problem, a typo that the resource redirect hid: the style's
    # Fluent singleton keeps its type tokens in a `typography` group, and these
    # five files read them off the singleton itself. Undefined assigned to a
    # string is a warning and a control drawn in the wrong font.
    (
        "Fluent.fontFamily",
        "Fluent.typography.fontFamily",
        "Fluent.fontFamily does not exist on the style's Fluent singleton",
    ),
    (
        "Fluent.fontBodySize",
        "Fluent.typography.body",
        "Fluent.fontBodySize does not exist either; body is the scaled 17px",
    ),
)


def apply_compat(rel: str, text: str, report: Report) -> str:
    for find, replace, why in COMPAT:
        found = text.count(find)
        if not found:
            continue
        text = text.replace(find, replace)
        report.compat_applied.append(f"`{rel}` — {found} x {why}")
    return text


# --------------------------------------------------------------------------
# Scaling primitives
# --------------------------------------------------------------------------


def scale_geom(value: float) -> float:
    """Scale a size. Hairlines (<2) pass through so dividers stay crisp."""
    if abs(value) < GEOM_MIN:
        return value
    return float(round(value * GEOM_SCALE))


def scale_font(value: float) -> float:
    """Scale a font size through the curated type map."""
    as_int = int(round(value))
    if as_int in FONT_MAP:
        return float(FONT_MAP[as_int])
    if as_int < 8:
        return value
    # Unmapped size: gentle 1.2x, but always at least +1 so it visibly grows.
    return float(max(as_int + 1, round(as_int * 1.2)))


def fmt_number(value: float) -> str:
    """Render a number the way the source file would: ints without a .0."""
    if value == int(value):
        return str(int(value))
    return f"{value:g}"


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------


@dataclass
class Report:
    config_scaled: int = 0
    config_frozen: int = 0
    config_fonts: int = 0
    geom_hist: dict[tuple[str, str], int] = field(default_factory=dict)
    font_hist: dict[tuple[str, str], int] = field(default_factory=dict)
    tokens_applied: dict[str, list[str]] = field(default_factory=dict)
    tokens_missing: dict[str, list[str]] = field(default_factory=dict)
    control_edits: list[str] = field(default_factory=list)
    patches_applied: list[str] = field(default_factory=list)
    patches_missed: list[str] = field(default_factory=list)
    compat_applied: list[str] = field(default_factory=list)
    qmldir_dropped: list[str] = field(default_factory=list)
    unknown_props: dict[str, int] = field(default_factory=dict)

    def note_geom(self, old: float, new: float) -> None:
        if old == new:
            return
        key = (fmt_number(old), fmt_number(new))
        self.geom_hist[key] = self.geom_hist.get(key, 0) + 1

    def note_font(self, old: float, new: float) -> None:
        if old == new:
            return
        key = (fmt_number(old), fmt_number(new))
        self.font_hist[key] = self.font_hist.get(key, 0) + 1

    def render(self, *, src: Path, dst: Path) -> str:
        lines = [
            "# FluentPySide scale report",
            "",
            "Generated by `tools/scale_fluent.py` — do not edit by hand.",
            "",
            f"- source: `{src}`",
            f"- output: `{dst}`",
            f"- geometry scale: **{GEOM_SCALE}x** "
            f"(values < {fmt_number(GEOM_MIN)} left alone as hairlines)",
            f"- type scale: curated map, body **14 -> {FONT_MAP[14]}px**",
            "",
            "The style module is relocated from `fluent_winui3/` to",
            f"`{DST_STYLE_DIR.as_posix()}/` so that",
            "`_installer.default_style_path()` resolves to the scaled copy",
            "instead of silently falling back to the style bundled in PySide6.",
            "",
            "## Layer 1 — Config.qml (Figma export)",
            "",
            f"- geometry properties scaled: **{self.config_scaled}**",
            f"- font sizes scaled: **{self.config_fonts}**",
            f"- properties deliberately frozen: **{self.config_frozen}**",
            "",
            "Frozen on purpose: `x`/`y` are sprite-atlas coordinates,",
            "`textHAlignment`/`textVAlignment` are `Qt.Align*` enum flags",
            "(4, 128, ...) that scaling would corrupt, `*Shadow` is metadata.",
            "",
        ]

        if self.geom_hist:
            lines += [
                "### Geometry value distribution",
                "",
                "| from | to | count |",
                "| ---: | ---: | ---: |",
            ]
            for (old, new), count in sorted(
                self.geom_hist.items(), key=lambda kv: -kv[1]
            ):
                lines.append(f"| {old} | **{new}** | {count} |")
            lines.append("")

        if self.font_hist:
            lines += [
                "### Font value distribution",
                "",
                "| from | to | count |",
                "| ---: | ---: | ---: |",
            ]
            for (old, new), count in sorted(
                self.font_hist.items(), key=lambda kv: -kv[1]
            ):
                lines.append(f"| {old} | **{new}** | {count} |")
            lines.append("")

        if self.unknown_props:
            lines += [
                "### Unrecognised numeric properties",
                "",
                "These appeared in Config.qml but are in neither list, so they",
                "were left untouched. Review and classify them.",
                "",
            ]
            for name, count in sorted(self.unknown_props.items()):
                lines.append(f"- `{name}` x{count}")
            lines.append("")
        else:
            lines += [
                "No unrecognised numeric properties — the whitelist and the",
                "freeze-list together cover the file exactly.",
                "",
            ]

        lines += ["## Layer 2 — Fluent.qml token singletons", ""]
        for rel in sorted(self.tokens_applied):
            applied = self.tokens_applied[rel]
            lines += [f"### {rel}", "", f"- tokens rewritten: **{len(applied)}**", ""]
            lines += [f"- {entry}" for entry in applied]
            lines.append("")
            missing = self.tokens_missing.get(rel) or []
            if missing:
                lines += ["**NOT found (upstream changed — review the table):**", ""]
                lines += [f"- `{entry}`" for entry in missing]
                lines.append("")

        lines += [
            "## Layer 3 — control QML (hardcoded literals)",
            "",
            f"- literals scaled: **{len(self.control_edits)}**",
            "",
            "Only bare-literal assignments to whitelisted property names are",
            "rewritten. Any binding containing an expression is left alone by",
            "construction, so animation durations, opacities, `z` values and",
            "computed sizes cannot be hit.",
            "",
        ]
        current = ""
        for entry in self.control_edits:
            path, _, change = entry.partition("|")
            if path != current:
                current = path
                lines += ["", f"### {path}", ""]
            lines.append(f"- {change}")
        lines.append("")

        lines += [
            "## Layer 4 — qmldir directives dropped",
            "",
            "`prefer` redirects every QML file load into the resources compiled",
            "into the style DLL. While it is present the scaled files on disk",
            "are dead code, so it is removed from the vendored copy. `plugin`",
            "is kept — the C++ types still have to register.",
            "",
        ]
        if self.qmldir_dropped:
            for entry in self.qmldir_dropped:
                lines.append(f"- {entry}")
        else:
            lines.append("- nothing dropped (upstream changed — verify by hand)")
        lines.append("")

        lines += [
            "## Layer 5 — targeted patches",
            "",
            "Sizes that FluentPySide writes *inside* an expression, where layer 3",
            "cannot reach them. Each one restores a relationship the generic",
            "scaling would otherwise break — a caption button that no longer",
            "fills its title bar, a dialog that caps its width before its text",
            "fits, a 3px indicator beside a 60px row.",
            "",
            f"- patches applied: **{len(self.patches_applied)}** of "
            f"**{len(self.patches_applied) + len(self.patches_missed)}**",
            "",
        ]
        for entry in self.patches_applied:
            lines.append(f"- {entry}")
        lines.append("")
        if self.patches_missed:
            lines += [
                "### NOT APPLIED — upstream text changed",
                "",
                "These are matched as exact text, so a reformat or a rename",
                "upstream stops them silently. Fix the table in",
                "`tools/scale_fluent.py` and re-run.",
                "",
            ]
            for entry in self.patches_missed:
                lines.append(f"- {entry}")
            lines.append("")

        lines += [
            "## Layer 6 — runtime compatibility",
            "",
            "Expressions that read a Qt API newer than the one this project",
            "runs on. They are invisible upstream because the resource redirect",
            "keeps these files from ever being parsed; layer 4 removes that",
            "redirect, so they become this tool's problem.",
            "",
            f"- substitutions: **{len(self.compat_applied)}** file(s)",
            "",
        ]
        for entry in self.compat_applied:
            lines.append(f"- {entry}")
        lines.append("")

        return "\n".join(lines)


# --------------------------------------------------------------------------
# Layer 1 — Config.qml
# --------------------------------------------------------------------------

CONFIG_RE = re.compile(
    r"^(?P<indent>\s*)readonly\s+property\s+(?P<type>real|int)\s+"
    r"(?P<name>\w+)\s*:\s*(?P<value>-?\d+(?:\.\d+)?)\s*$"
)


def transform_config(text: str, report: Report) -> str:
    out: list[str] = []
    for line in text.splitlines():
        match = CONFIG_RE.match(line)
        if match is None:
            out.append(line)
            continue

        name = match.group("name")
        value = float(match.group("value"))

        if name in FROZEN_PROPS:
            report.config_frozen += 1
            out.append(line)
            continue

        if name in FONT_PROPS:
            new_value = scale_font(value)
            report.config_fonts += 1
            report.note_font(value, new_value)
        elif name in SCALE_PROPS:
            new_value = scale_geom(value)
            report.config_scaled += 1
            report.note_geom(value, new_value)
        else:
            report.unknown_props[name] = report.unknown_props.get(name, 0) + 1
            out.append(line)
            continue

        out.append(
            f"{match.group('indent')}readonly property {match.group('type')} "
            f"{name}: {fmt_number(new_value)}"
        )

    trailing = "\n" if text.endswith("\n") else ""
    return "\n".join(out) + trailing


# --------------------------------------------------------------------------
# Layer 2 — Fluent.qml
# --------------------------------------------------------------------------


def transform_fluent_tokens(text: str, rel: str, report: Report) -> str:
    applied: list[str] = []
    missing: list[str] = []
    for name, (qml_type, old, new) in FLUENT_QML_TOKENS.items():
        pattern = re.compile(
            rf"(readonly\s+property\s+{qml_type}\s+{re.escape(name)}\s*:\s*)"
            rf"{re.escape(old)}\b"
        )
        text, count = pattern.subn(rf"\g<1>{new}", text)
        if count:
            applied.append(f"`{name}` {old} -> **{new}**")
        else:
            missing.append(f"{qml_type} {name}: {old}")
    report.tokens_applied[rel] = applied
    report.tokens_missing[rel] = missing
    return text


# --------------------------------------------------------------------------
# Layer 3 — control QML
# --------------------------------------------------------------------------

# Anchored at end of line so ONLY bare literals match. `width: parent.width - 8`
# or `duration: Fluent.anim.speed` can never be rewritten by this.
CONTROL_RE = re.compile(
    r"^(?P<head>\s*(?:readonly\s+)?(?:property\s+(?:real|int|double)\s+)?"
    r"(?P<prefix>(?:[A-Za-z_]\w*\.)*)(?P<name>[A-Za-z_]\w*)\s*:\s*)"
    r"(?P<value>-?\d+(?:\.\d+)?)"
    r"(?P<tail>\s*(?://.*)?)$"
)


def transform_control(text: str, rel: str, report: Report) -> str:
    out: list[str] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        match = CONTROL_RE.match(line)
        if match is None:
            out.append(line)
            continue

        stripped = line.lstrip()
        if stripped.startswith(("//", "*", "/*")):
            out.append(line)
            continue

        name = match.group("name")
        qualified = f"{match.group('prefix')}{name}"
        if qualified in CONTROL_FROZEN_PREFIXED:
            out.append(line)
            continue

        value = float(match.group("value"))

        if name in CONTROL_FONT_PROPS:
            new_value = scale_font(value)
        elif name in CONTROL_GEOM_PROPS:
            new_value = scale_geom(value)
        else:
            out.append(line)
            continue

        if new_value == value:
            out.append(line)
            continue

        report.control_edits.append(
            f"{rel}|line {lineno}: `{qualified}` "
            f"{fmt_number(value)} -> **{fmt_number(new_value)}**"
        )
        out.append(
            f"{match.group('head')}{fmt_number(new_value)}{match.group('tail')}"
        )

    trailing = "\n" if text.endswith("\n") else ""
    return "\n".join(out) + trailing


# --------------------------------------------------------------------------
# Layer 4 — qmldir
# --------------------------------------------------------------------------


def transform_qmldir(text: str, rel: str, report: Report) -> str:
    out: list[str] = []
    for line in text.splitlines():
        if line.strip().startswith(QMLDIR_DROP_PREFIXES):
            report.qmldir_dropped.append(f"`{rel}` — dropped `{line.strip()}`")
            continue
        out.append(line)
    trailing = "\n" if text.endswith("\n") else ""
    return "\n".join(out) + trailing


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

# Tool caches and VCS metadata, none of which belong in a vendored artifact.
# The source tree is somebody's working directory, so it accumulates them: the
# first run of this script carried a .ruff_cache into vendor/ for exactly that
# reason. Byte-copying is deliberately indiscriminate everywhere else — the DLL,
# the qmltypes, the sprite atlases and the icon font all have to come across
# untouched — so the filter is the only place this can be caught.
IGNORE = shutil.ignore_patterns(
    "__pycache__",
    "*.pyc",
    "*.pyo",
    ".ruff_cache",
    ".mypy_cache",
    ".pytest_cache",
    ".git",
    ".gitignore",
    ".DS_Store",
)


def vendor(src: Path, dst: Path, *, check: bool) -> Report:
    """Build the scaled copy. With ``check``, analyse in place and write nothing."""
    report = Report()

    src_style = src / SRC_STYLE_DIR
    src_controls = src / CONTROLS_DIR
    if not (src_style / "Config.qml").is_file():
        raise SystemExit(f"not a FluentPySide package: {src}")

    dst_style = dst / DST_STYLE_DIR
    dst_controls = dst / CONTROLS_DIR

    if not check:
        if dst.exists():
            shutil.rmtree(dst)
        dst.mkdir(parents=True)
        # Python package files, verbatim.
        for py in sorted(src.glob("*.py")):
            shutil.copy2(py, dst / py.name)
        # Both QML modules, verbatim first; the scaled files overwrite below.
        # Byte-copying carries the DLL, plugins.qmltypes, the PNG indicator
        # atlases (light/, dark/, icons/) and the icon font across untouched.
        shutil.copytree(src_style, dst_style, ignore=IGNORE)
        shutil.copytree(src_controls, dst_controls, ignore=IGNORE)

    def write(path: Path, text: str) -> None:
        if not check:
            path.write_text(text, encoding="utf-8", newline="\n")

    # -- layer 1: the Figma export --
    write(
        dst_style / "Config.qml",
        transform_config((src_style / "Config.qml").read_text(encoding="utf-8"), report),
    )

    # -- layer 2: BOTH token singletons --
    # The style's own Fluent is read by the 52 styled standard controls;
    # FluentControls' Fluent is read by the 47 custom controls. Scaling one and
    # not the other leaves half the library at desktop density.
    for src_dir, dst_dir, label in (
        (src_style, dst_style, f"{DST_STYLE_DIR.as_posix()}/Fluent.qml"),
        (src_controls, dst_controls, f"{CONTROLS_DIR}/Fluent.qml"),
    ):
        write(
            dst_dir / "Fluent.qml",
            transform_fluent_tokens(
                (src_dir / "Fluent.qml").read_text(encoding="utf-8"), label, report
            ),
        )

    # -- layer 3: hardcoded literals in the controls themselves --
    # Layer 5 rides along here: the patches operate on the layer-3 output, so
    # each file is read once and written once.
    skip = {"Config.qml", "Fluent.qml"}
    for src_dir, dst_dir, prefix in (
        (src_style, dst_style, DST_STYLE_DIR.as_posix()),
        (src_style / "impl", dst_style / "impl", f"{DST_STYLE_DIR.as_posix()}/impl"),
        (src_controls, dst_controls, CONTROLS_DIR),
    ):
        if not src_dir.is_dir():
            continue
        for qml in sorted(src_dir.glob("*.qml")):
            if qml.name in skip:
                continue
            rel = f"{prefix}/{qml.name}"
            text = transform_control(qml.read_text(encoding="utf-8"), rel, report)
            text = apply_patches(rel, text, report)
            write(dst_dir / qml.name, apply_compat(rel, text, report))

    # -- layer 4: defeat the resource redirect --
    for src_dir, dst_dir, prefix in (
        (src_style, dst_style, DST_STYLE_DIR.as_posix()),
        (src_style / "impl", dst_style / "impl", f"{DST_STYLE_DIR.as_posix()}/impl"),
    ):
        qmldir = src_dir / "qmldir"
        if not qmldir.is_file():
            continue
        write(
            dst_dir / "qmldir",
            transform_qmldir(
                qmldir.read_text(encoding="utf-8"), f"{prefix}/qmldir", report
            ),
        )

    return report


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Scale FluentPySide up for touch.")
    parser.add_argument(
        "--src",
        type=Path,
        default=root.parent / "FluentPySide-main" / "fluentpyside",
        help="pristine fluentpyside package directory",
    )
    parser.add_argument(
        "--dst",
        type=Path,
        default=root / "vendor" / "fluentpyside",
        help="output directory for the scaled copy",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=root / "SCALE_REPORT.md",
        help="where to write the audit report",
    )
    parser.add_argument("--geom", type=float, help="override the geometry scale")
    parser.add_argument(
        "--check",
        action="store_true",
        help="analyse and report without writing the vendored copy",
    )
    args = parser.parse_args(argv)

    if args.geom:
        global GEOM_SCALE
        GEOM_SCALE = args.geom

    src = args.src.resolve()
    dst = args.dst.resolve()
    report = vendor(src, dst, check=args.check)

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(report.render(src=src, dst=dst), encoding="utf-8")

    print(f"Config.qml     geometry scaled : {report.config_scaled}")
    print(f"Config.qml     fonts scaled    : {report.config_fonts}")
    print(f"Config.qml     frozen          : {report.config_frozen}")
    for rel, applied in sorted(report.tokens_applied.items()):
        missing = len(report.tokens_missing.get(rel) or [])
        note = f"  MISSING {missing}" if missing else ""
        print(f"tokens {rel:<46} : {len(applied)}{note}")
    print(f"control literals scaled        : {len(report.control_edits)}")
    print(
        f"targeted patches applied       : {len(report.patches_applied)}"
        f"/{len(report.patches_applied) + len(report.patches_missed)}"
    )
    print(f"compatibility substitutions    : {len(report.compat_applied)} file(s)")
    print(f"qmldir directives dropped      : {len(report.qmldir_dropped)}")
    if report.unknown_props:
        print(f"UNKNOWN properties             : {len(report.unknown_props)} (see report)")
    print(f"report -> {args.report}")
    if not args.check:
        print(f"vendored -> {dst}")

    if report.patches_missed:
        # The copy is written and otherwise valid, but a patch that did not
        # match means a size the generic layers cannot reach was left at desktop
        # density — a visibly broken title bar, most likely. Say so and fail.
        print()
        for entry in report.patches_missed:
            print(f"PATCH NOT APPLIED: {entry}")
        print(
            "the vendored copy is written but incomplete — update PATCHES in "
            "tools/scale_fluent.py and re-run"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
