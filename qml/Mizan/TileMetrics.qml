pragma Singleton

import QtQuick

/*
 * WHAT THE TILL'S WALL IS WEARING — published where it is decided, read where
 * it has to be matched.
 *
 * The arrange screen exists so a cashier's hand goes to the same place every
 * time, which means the tiles it shows must BE the till's tiles: the same
 * count in a row, the same card shape, the same photo-or-not. It cannot
 * re-derive that by itself — the dialog's own width has nothing to do with the
 * window's, so arithmetic over it answers a different question than the wall
 * does. So the wall's answer travels: PosPage publishes what its grid decided,
 * and the dialog reads it.
 *
 * WHY A SINGLETON AND NOT THE DIALOG'S CONTEXT
 *
 * A context would be a snapshot: opened from a 1920px window, closed, the
 * window narrowed, opened again — fine. But it also freezes WHILE the dialog
 * is up, and the one thing this screen promises is "exactly what the till
 * shows". A property is live: if the wall's count changes, the dialog's grid
 * changes with it in the same pass, because they are the same number rather
 * than two copies of one.
 *
 * `columns: 0` means THE TILL HAS NOT SAID — the page is not on screen, or it
 * has not loaded yet — and the reader falls back to the token. Nothing else
 * should ever write these; they are the wall's own figures, relayed.
 */
QtObject {
    /* The wall's column count, or 0 for "not published". */
    property int columns: 0

    /* Whether the wall's cards carry the photo band (the shop's image setting
       AND room for it — the same answer the till's grid computed). */
    property bool mediaWall: false

    /* Whether the till is on screen at all. A count published by a page that
       has since been left behind is a stale answer, not a live one. */
    property bool live: false
}
