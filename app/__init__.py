"""The Python side of MIZAN POS 2.

Only the bridge lives here for now: the objects QML reaches through the `app`
context property. The business logic itself is still pos/'s — see
`app.bridge.legacy` for the one seam between the two trees and why it is a seam
rather than a copy.
"""
