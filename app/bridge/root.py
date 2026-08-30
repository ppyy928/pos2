"""The object QML reaches as `app`.

    app.i18n        strings, language, direction          -> Strings.qml
    app.auth        login()                               -> LoginPage.qml
    app.session     can(permission)                       -> RowActions, pages
    app.workflows   open(key, context)                    -> every page, DialogHost
    app.pos         the till                              -> PosPage.qml
    app.products    the catalogue                         -> ProductsPage.qml, dialogs
    app.sales       sales                                 -> SalesPage.qml, dialogs
    app.returns     goods that came back                  -> ReturnsPage.qml
    app.customers   customers and their debt               -> CustomersPage.qml
    app.cash        the drawer and its movements          -> CashPage.qml
    app.payments    the payments register                 -> PaymentsPage.qml
    app.employees   accounts, roles and permissions       -> EmployeesPage.qml
    app.purchases   deliveries received                   -> PurchasesPage.qml
    app.suppliers   who the shop buys from                -> the suppliers dialog
    app.settings    the key/value store, grouped          -> SettingsPage.qml
    app.backups     database copies                       -> BackupPage.qml
    app.dashboard   today, in six figures                 -> DashboardPage.qml
    app.reports     six tabs of detailed reporting        -> ReportsPage.qml
    app.catalogue   categories, units, multi-units, order -> the catalogue dialogs
    app.scanner     the barcode burst decoder             -> the till, directly

The constant properties are constant on purpose: these objects are created with
the bridge and live as long as it does, so QML can bind to them once instead of
re-resolving them. Signing out replaces the *contents* of the session, never the
session object.
"""

from __future__ import annotations

from PySide6.QtCore import Property, QCoreApplication, QObject

from .admin import Backups, Dashboard, Reports, Settings
from .auth import Auth, Session
from .cash import Cash, Payments
from .catalogue import Catalogue
from .customers import Customers
from .employees import Employees
from .i18n import I18n
from .printing import Printing
from .products import Products
from .purchases import Purchases, Suppliers
from .sales import Returns, Sales
from .scanner import Scanner
from .stock import Stock
from .till import Till
from .workflows import Workflows


class App(QObject):
    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)

        self._i18n = I18n(self)
        self._session = Session(self)
        self._auth = Auth(self)
        self._workflows = Workflows(self._i18n, self._session, self)
        self._pos = Till(self._i18n, self._session, self)
        self._products = Products(self._i18n, self)
        self._customers = Customers(self._i18n, self)
        self._sales = Sales(self._i18n, self)
        self._returns = Returns(self._i18n, self)
        self._cash = Cash(self._i18n, self)
        self._payments = Payments(self._i18n, self)
        self._employees = Employees(self._i18n, self)
        self._purchases = Purchases(self._i18n, self)
        self._suppliers = Suppliers(self._i18n, self)
        self._settings = Settings(self._i18n, self)
        self._backups = Backups(self._i18n, self)
        self._dashboard = Dashboard(self._i18n, self)
        self._reports = Reports(self._i18n, self)
        self._catalogue = Catalogue(self._i18n, self)
        self._printing = Printing(self._i18n, self)
        self._stock = Stock(self._i18n, self)
        self._scanner = Scanner(self)

        # The session records whoever Auth verified, and it is connected here
        # rather than in Auth so that Auth has no opinion about what happens
        # after a password checks out. Connected before any QML exists, so
        # session.can() is already true by the time the shell reacts to the same
        # signal.
        self._auth.succeeded.connect(self._session.adopt)

        # A product created or edited anywhere moves what the till may sell; a
        # sale or a return moves the stock behind it.
        self._products.invalidated.connect(self._pos.invalidated)
        self._sales.invalidated.connect(self._pos.invalidated)
        # A return moves stock and a debt, and both lists show it.
        self._sales.invalidated.connect(self._returns.reload)
        self._returns.invalidated.connect(self._sales.reload)
        self._returns.invalidated.connect(self._pos.invalidated)
        self._pos.saleFinished.connect(lambda _number: self._sales.reload())
        # A sale puts money in the drawer, and a payment settles a debt the
        # customers page is showing.
        self._pos.saleFinished.connect(lambda _number: self._cash.load())
        self._payments.invalidated.connect(self._customers.reload)
        # A delivery raises stock, so the till's grid is stale; paying a
        # supplier changes what the purchases page reports as owed.
        self._purchases.invalidated.connect(self._pos.invalidated)
        self._suppliers.invalidated.connect(self._purchases.reload)
        # Categories, tile order and favourites all change what the till
        # shows, and multi-units change what a scan resolves to.
        self._catalogue.changed.connect(self._pos.invalidated)
        self._catalogue.changed.connect(self._products.invalidated)

        # Stock moved by a stocktake, a write-off or a batch edit is stock the
        # catalogue and the till are showing a stale figure for.
        self._stock.invalidated.connect(self._products.invalidated)
        self._stock.invalidated.connect(self._pos.invalidated)

        # A finished sale prints itself when the setting says so. Connected here
        # rather than in the till, because the till's job ends when the money is
        # recorded and the receipt belongs to the sale.
        self._pos.saleRecorded.connect(self._print_sale)

        # An invoice loaded into the till and re-rung leaves by a different road:
        # the same cart and the same two buttons, but Sales.save rather than a new
        # sale. Routed here so the till never learns how a sale is written and Sales
        # never learns there is a cart.
        self._pos.saleEditRequested.connect(self._save_sale_edit)
        self._sales.saved.connect(lambda _sale: self._pos.clear())

        # A scanned code goes straight to the till: scan() adds it if it exists and
        # says so if it does not, which is the same path the keypad's Apply takes.
        # No screen is involved, because a scan works whatever screen is open.
        self._scanner.scanned.connect(self._pos.scan)

        # Installed here rather than from run.py: the application is the only
        # object that sees every key, and nothing outside this file should have to
        # know that one of these controllers is watching it.
        self._scanner.install(QCoreApplication.instance())

    def _print_sale(self, sale_id: int) -> None:
        if sale_id and self._sales.autoPrint:
            self._sales.printReceipt(sale_id, self._session.name)

    def _save_sale_edit(self, document: object, sale_id: int) -> None:
        """Commit an invoice that was rewritten in the till.

        `Sales.save` owns every rule about it — a returned sale is refused, the paid
        figure replaces rather than adds, the debt reconciles by the delta — so this
        is a wire and nothing more. The cart is emptied by `Sales.saved` above, so a
        refusal leaves the operator holding exactly what they were editing.
        """
        self._sales.save(document, int(sale_id))

    @Property(QObject, constant=True)
    def printing(self) -> QObject:
        return self._printing

    @Property(QObject, constant=True)
    def stock(self) -> QObject:
        return self._stock

    @Property(QObject, constant=True)
    def i18n(self) -> QObject:
        return self._i18n

    @Property(QObject, constant=True)
    def auth(self) -> QObject:
        return self._auth

    @Property(QObject, constant=True)
    def session(self) -> QObject:
        return self._session

    @Property(QObject, constant=True)
    def workflows(self) -> QObject:
        return self._workflows

    @Property(QObject, constant=True)
    def pos(self) -> QObject:
        return self._pos

    @Property(QObject, constant=True)
    def products(self) -> QObject:
        return self._products

    @Property(QObject, constant=True)
    def customers(self) -> QObject:
        return self._customers

    @Property(QObject, constant=True)
    def sales(self) -> QObject:
        return self._sales

    @Property(QObject, constant=True)
    def returns(self) -> QObject:
        return self._returns

    @Property(QObject, constant=True)
    def cash(self) -> QObject:
        return self._cash

    @Property(QObject, constant=True)
    def payments(self) -> QObject:
        return self._payments

    @Property(QObject, constant=True)
    def employees(self) -> QObject:
        return self._employees

    @Property(QObject, constant=True)
    def purchases(self) -> QObject:
        return self._purchases

    @Property(QObject, constant=True)
    def suppliers(self) -> QObject:
        return self._suppliers

    @Property(QObject, constant=True)
    def settings(self) -> QObject:
        return self._settings

    @Property(QObject, constant=True)
    def backups(self) -> QObject:
        return self._backups

    @Property(QObject, constant=True)
    def dashboard(self) -> QObject:
        return self._dashboard

    @Property(QObject, constant=True)
    def reports(self) -> QObject:
        return self._reports

    @Property(QObject, constant=True)
    def catalogue(self) -> QObject:
        return self._catalogue

    @Property(QObject, constant=True)
    def scanner(self) -> QObject:
        return self._scanner
