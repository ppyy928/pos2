"""Employees and what they may do, behind `app.employees`.

    read      busy, error, rows, roles, permissionGroups
    call      load(search), save(data, id), setActive(id, on),
              changePassword(id, current, new)
    emits     invalidated(), saved(employee), rejected(message)

WHY THE PERMISSION LIST COMES FROM PYTHON

`PERMISSION_GROUPS` is the definition of what this application can do — six groups
of named permissions, and a role is a default selection from them. A copy of that
list in QML would be a second definition that could quietly disagree with the one
`session.can()` checks, which is the one that decides whether a button works. So
the groups, their permissions and the role defaults all arrive from here, already
labelled.

WHAT THIS DOES NOT DO

It cannot delete an employee: pos has no delete for one either, and for good
reason — sales carry `created_by`, so a removed employee would orphan the audit
trail. Deactivating is the operation, and it is what stops them signing in.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot

from . import interop, legacy


class Employees(QObject):
    rowsChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    invalidated = Signal()
    saved = Signal("QVariant")
    rejected = Signal(str)

    #: Role and permission labels are translated, so the two catalogue properties
    #: below are not constant: a language change has to rebuild them like every
    #: other visible string.
    catalogueChanged = Signal()

    def __init__(self, i18n: QObject, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        i18n.languageChanged.connect(self.catalogueChanged)
        self._rows: list[dict] = []
        self._busy = False
        self._error = ""
        self._search = ""

    # =====================================================================
    # STATE
    # =====================================================================
    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error

    @Property(int, notify=rowsChanged)
    def total(self) -> int:
        return len(self._rows)

    @Property("QVariantList", notify=rowsChanged)
    def rows(self) -> list:
        return self._rows

    @Property("QVariantList", notify=catalogueChanged)
    def roles(self) -> list:
        """The three roles, with the permissions each one grants by default."""
        database = self._database(quiet=True)
        defaults = getattr(database, "ROLE_DEFAULTS", {}) if database else {}
        return [
            {
                "key": key,
                "label": self._i18n.text(f"employees.role.{key}"),
                "permissions": list(defaults.get(key) or []),
            }
            for key in ("admin", "seller", "cashier")
        ]

    @Property("QVariantList", notify=catalogueChanged)
    def permissionGroups(self) -> list:
        """The permission catalogue, grouped as pos groups it, with labels."""
        database = self._database(quiet=True)
        groups = getattr(database, "PERMISSION_GROUPS", {}) if database else {}
        return [
            {
                "key": group,
                "label": self._i18n.text(f"perm.group.{group}"),
                "permissions": [
                    {"key": permission,
                     "label": self._i18n.text(f"perm.{permission}")}
                    for permission in permissions
                ],
            }
            for group, permissions in groups.items()
        ]

    # =====================================================================
    # QUERIES
    # =====================================================================
    @Slot(str)
    def load(self, search: str) -> None:
        database = self._database()
        if database is None:
            return
        self._search = (search or "").strip().lower()
        self._set_busy(True)
        try:
            rows = database.fetch_employees()
            if self._search:
                rows = [row for row in rows
                        if self._search in (row.get("name") or "").lower()
                        or self._search in (row.get("username") or "").lower()]
            self._rows = [self._row(row) for row in rows]
            self._set_error("")
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            self._rows = []
        finally:
            self._set_busy(False)
        self.rowsChanged.emit()

    @Slot()
    def reload(self) -> None:
        self.load(self._search)

    @Slot(int, result="QVariant")
    def rowAt(self, index: int) -> object:
        if 0 <= index < len(self._rows):
            return self._rows[index]
        return None

    @Slot(int, result="QVariant")
    def employee(self, employee_id: int) -> object:
        for row in self._rows:
            if row["id"] == employee_id:
                return row
        return None

    # =====================================================================
    # MUTATIONS
    # =====================================================================
    @Slot("QVariant", int)
    def save(self, data: object, employee_id: int) -> None:
        values = interop.as_dict(data)
        name = str(values.get("name") or "").strip()
        username = str(values.get("username") or "").strip()
        if not name:
            self.rejected.emit(self._i18n.text("employees.name.required"))
            return
        if not username:
            self.rejected.emit(self._i18n.text("employees.username.required"))
            return
        password = str(values.get("password") or "")
        if not employee_id and not password:
            # A new account with no password could be signed into by anybody who
            # knows the username, since verify_password compares against an empty
            # hash. pos's form requires one on create for the same reason.
            self.rejected.emit(self._i18n.text(
                "employees.password.required",
                "A new account needs a password."))
            return

        database = self._database()
        if database is None:
            return

        payload = {
            "name": name,
            "username": username,
            "role": str(values.get("role") or "seller"),
            "active": bool(values.get("active", True)),
            "permissions": [str(p) for p in (values.get("permissions") or [])],
        }
        if password:
            payload["password"] = password

        try:
            employee = database.save_employee(payload, int(employee_id) or None)
        except Exception as exc:  # noqa: BLE001
            # "duplicate username: amine" is the sentence that names the clash.
            self.rejected.emit(str(exc))
            return
        self.saved.emit(dict(employee))
        self.invalidated.emit()
        self.reload()

    @Slot(int, bool)
    def setActive(self, employee_id: int, value: bool) -> None:
        """Deactivating is the closest thing to removal: authenticate() only ever
        looks at active accounts, so this is what closes the door."""
        row = self.employee(employee_id)
        if row is None:
            return
        database = self._database()
        if database is None:
            return
        try:
            database.save_employee({
                "name": row["name"],
                "username": row["username"],
                "role": row["role"],
                "active": bool(value),
                "permissions": row.get("permissions") or [],
            }, int(employee_id))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.invalidated.emit()
        self.reload()

    @Slot(int, str, str)
    def changePassword(self, employee_id: int, current: str, new: str) -> None:
        """The operator's own password: the current one has to be right, which is
        why this is not the same call as an administrator resetting one through
        save()."""
        database = self._database()
        if database is None:
            return
        try:
            database.change_employee_password(int(employee_id), str(current),
                                              str(new))
        except Exception as exc:  # noqa: BLE001
            self.rejected.emit(str(exc))
            return
        self.saved.emit({"id": employee_id})

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _row(self, row: dict) -> dict:
        role = row.get("role") or ""
        permissions = row.get("permissions") or []
        return {
            "id": row["id"],
            "name": row["name"],
            "username": row.get("username") or "",
            "role": role,
            "role_label": self._i18n.text(f"employees.role.{role}") if role else "",
            "active": bool(row.get("active", 1)),
            "permissions": list(permissions),
            # A count rather than a list in the table: eleven permission names do
            # not fit in a cell, and the number is what tells two roles apart.
            "permission_count": str(len(permissions)),
        }

    def _database(self, quiet: bool = False):
        try:
            return legacy.database()
        except Exception as exc:  # noqa: BLE001
            if not quiet:
                self._set_error(str(exc))
            return None

    def _set_busy(self, value: bool) -> None:
        if self._busy == value:
            return
        self._busy = value
        self.busyChanged.emit()

    def _set_error(self, message: str) -> None:
        if self._error == message:
            return
        self._error = message
        self.errorChanged.emit()
