pragma Singleton
import QtQuick

/*
 * The 12 MIZAN modules, in one place.
 *
 * This is data, not UI. The nav rail, the dashboard quick-action tiles, page
 * headers, chart series and badge colours all read from here, which is the
 * only way they can be guaranteed to agree about what "purchases" is called
 * and what colour it is.
 *
 * Order follows pos's original nav so existing operators keep their muscle
 * memory; the `section` field adds the grouping pos never had. `settings` and
 * `backup` are pinned to the bottom of the rail.
 *
 * `titleKey` is the i18n lookup key. Until the i18n bridge lands, `title`
 * (English) is displayed as-is — see NavRail's titleFor().
 */
QtObject {
    id: root

    // Icon names verified present in FluentSystemIcons-Index.js.
    readonly property var all: [
        {
            key: "dashboard", titleKey: "nav.dashboard", title: "Dashboard",
            icon: "ic_fluent_data_pie_20_regular",
            page: "pages/DashboardPage.qml", section: ""
        },
        {
            key: "pos", titleKey: "nav.pos", title: "Point of Sale",
            icon: "ic_fluent_cart_20_regular",
            page: "pages/PosPage.qml", section: ""
        },
        {
            key: "sales", titleKey: "nav.sales", title: "Sales",
            icon: "ic_fluent_receipt_money_20_regular",
            page: "pages/SalesPage.qml", section: "sell"
        },
        {
            key: "returns",
            titleKey: "nav.returns",
            title: "Returns",
            icon: "ic_fluent_arrow_undo_20_regular",
            section: "sell",
            page: "pages/ReturnsPage.qml"
        },
        {
            key: "customers", titleKey: "nav.customers", title: "Customers",
            icon: "ic_fluent_people_team_20_regular",
            page: "pages/CustomersPage.qml", section: "sell"
        },
        {
            key: "products", titleKey: "nav.products", title: "Products",
            icon: "ic_fluent_box_multiple_20_regular",
            page: "pages/ProductsPage.qml", section: "stock"
        },
        {
            key: "purchases", titleKey: "nav.purchases", title: "Purchases",
            icon: "ic_fluent_vehicle_truck_profile_20_regular",
            page: "pages/PurchasesPage.qml", section: "stock"
        },
        {
            key: "suppliers",
            titleKey: "nav.suppliers",
            title: "Suppliers",
            icon: "ic_fluent_vehicle_truck_profile_20_regular",
            section: "stock",
            page: "pages/SuppliersPage.qml"
        },
        {
            key: "payments", titleKey: "nav.payments", title: "Payments",
            icon: "ic_fluent_wallet_20_regular",
            page: "pages/PaymentsPage.qml", section: "money"
        },
        {
            key: "cash", titleKey: "nav.cash", title: "Cash",
            icon: "ic_fluent_money_hand_20_regular",
            page: "pages/CashPage.qml", section: "money"
        },
        {
            key: "employees", titleKey: "nav.employees", title: "Employees",
            icon: "ic_fluent_person_board_20_regular",
            page: "pages/EmployeesPage.qml", section: "manage"
        },
        {
            key: "reports", titleKey: "nav.reports", title: "Reports",
            icon: "ic_fluent_data_bar_vertical_20_regular",
            page: "pages/ReportsPage.qml", section: "manage"
        },
        {
            key: "settings", titleKey: "nav.settings", title: "Settings",
            icon: "ic_fluent_settings_20_regular",
            page: "pages/SettingsPage.qml", section: "bottom"
        },
        {
            key: "backup", titleKey: "nav.backup", title: "Backup",
            icon: "ic_fluent_cloud_arrow_up_20_regular",
            page: "pages/BackupPage.qml", section: "bottom"
        }
    ]

    // Section captions, shown only while the rail is expanded. "" is the
    // ungrouped head of the list (Dashboard + POS) and never draws a caption.
    readonly property var sectionTitles: ({
        "sell":   "SELL",
        "stock":  "STOCK",
        "money":  "MONEY",
        "manage": "MANAGE"
    })

    readonly property string defaultKey: "pos"

    /*
     * Modules whose page file actually exists. Flip an entry to true as each
     * page lands.
     *
     * This is declared rather than inferred from a failed load on purpose: if
     * PageHost treated "component failed" as "not built yet", a real QML syntax
     * error in a finished page would render as a friendly placeholder and cost
     * hours to find. Unbuilt is a statement; a load failure is a bug.
     */
    readonly property var built: ({
        "products": true,
        "pos": true,
        "sales": true,
        "customers": true,
        "cash": true,
        "payments": true,
        "employees": true,
        "purchases": true,
        "dashboard": true,
        "reports": true,
        "settings": true,
        "backup": true,
        "returns": true,
        "suppliers": true
    })

    /*
     * "Take me to that screen", from a page that cannot reach the shell.
     *
     * A page is created by PageHost in PageHost's own context, so ids declared in
     * Main.qml are not in its scope chain: a dashboard card cannot call host.show()
     * however obvious that looks. This singleton is imported by every page and by
     * the shell, which makes it the one object both ends already share — so the
     * request travels through it and Main.qml is the only thing that acts on it.
     */
    signal requested(string key)

    function request(key) {
        if (isBuilt(key))
            requested(key)
    }

    function isBuilt(key) {
        return built[key] === true
    }

    function byKey(key) {
        for (var i = 0; i < all.length; i++)
            if (all[i].key === key) return all[i]
        return null
    }

    /* Everything above the bottom-pinned pair, in declaration order. */
    function mainItems() {
        return all.filter(function (d) { return d.section !== "bottom" })
    }

    function bottomItems() {
        return all.filter(function (d) { return d.section === "bottom" })
    }
}
