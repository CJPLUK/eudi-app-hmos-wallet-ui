/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of the iOS `NSNotification.Name` constants the workers post plus a minimal
 * in-process NotificationCenter (iOS `NotificationCenter.default`). The wallet's
 * notification names (ReIssuanceDetailsRefresh / RevocationDashboard /
 * DocumentTabRefresh / DocumentDetailsRefresh) are observed by the feature layer.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex

/** Mirrors the wallet's `NSNotification.Name` constants. */
public enum NotificationName <: Equatable<NotificationName> & Hashable {
    | ReIssuanceDetailsRefresh
    | RevocationDashboard
    | DocumentTabRefresh
    | DocumentDetailsRefresh
    // Shared-toolbar seam: the Dashboard owns ONE nav bar (leading menu + title +
    // trailing actions) across the Home/Documents/History tabs, mirroring iOS.
    // The trailing filter button lives in that shared bar, so it posts these to
    // the tab that owns the filter overlay, and each tab posts DashboardToolbarSync
    // back so the bar can enable/gray its filter from the tab's row count.
    | DocumentOpenFilters
    | TransactionOpenFilters
    | DashboardToolbarSync
    // Deferred docs completed issuance — the dashboard shows the
    // "Documents issued" sheet ABOVE the floating tab bar (payload rows are
    // carried by the dashboard-layer singleton, not the notification).
    | DeferredDocsIssued
    // History tab must re-pull its rows (e.g. after filters apply).
    | TransactionTabRefresh
    // A new credential-offer deep link arrived while the offer screen is
    // foreground — the screen reloads with the new uri instead of re-pushing
    // (iOS NSNotification.CredentialOffer, DeepLinkController foreground path).
    | CredentialOfferNew

    public prop rawValue: String {
        get() {
            match (this) {
                case ReIssuanceDetailsRefresh => "ReIssuanceDetailsRefresh"
                case RevocationDashboard => "RevocationDashboard"
                case DocumentTabRefresh => "DocumentTabRefresh"
                case DocumentDetailsRefresh => "DocumentDetailsRefresh"
                case DocumentOpenFilters => "DocumentOpenFilters"
                case TransactionOpenFilters => "TransactionOpenFilters"
                case DashboardToolbarSync => "DashboardToolbarSync"
                case DeferredDocsIssued => "DeferredDocsIssued"
                case TransactionTabRefresh => "TransactionTabRefresh"
                case CredentialOfferNew => "CredentialOfferNew"
            }
        }
    }
    public operator func ==(o: NotificationName): Bool { this.rawValue == o.rawValue }
    public operator func !=(o: NotificationName): Bool { !(this == o) }
    public func hashCode(): Int64 { this.rawValue.hashCode() }
}

/** A delivered notification: a name plus its optional userInfo payloads. */
public class Notification {
    public let name: NotificationName
    public let ids: ?Array<String>
    public let map: ?HashMap<String, String>
    public init(name!: NotificationName, ids!: ?Array<String> = None, map!: ?HashMap<String, String> = None) {
        this.name = name
        this.ids = ids
        this.map = map
    }
}

/**
 * Mirrors `NotificationCenter.default` — an in-process publish/subscribe hub.
 * Feature view-models register observers; the workers post on revocation/re-issue.
 */
public class NotificationCenter {
    private static let lock = Mutex()
    private static let observers = HashMap<String, ArrayList<(Notification) -> Unit>>()

    /** Mirrors `addObserver(forName:...)`. */
    public static func addObserver(name: NotificationName, observer: (Notification) -> Unit): Unit {
        synchronized(lock) {
            let key = name.rawValue
            match (observers.get(key)) {
                case Some(list) => list.add(observer)
                case None =>
                    let list = ArrayList<(Notification) -> Unit>()
                    list.add(observer)
                    observers.add(key, list)
            }
        }
    }

    static func deliver(notification: Notification): Unit {
        var snapshot = ArrayList<(Notification) -> Unit>()
        synchronized(lock) {
            match (observers.get(notification.name.rawValue)) {
                case Some(list) => for (o in list) { snapshot.add(o) }
                case None => ()
            }
        }
        for (o in snapshot) { o(notification) }
    }

    /** Post with no userInfo. */
    public static func post(name: NotificationName): Unit {
        deliver(Notification(name: name))
    }

    /** Post with `["ids": [...]]` userInfo. */
    public static func postIds(name: NotificationName, info: HashMap<String, Array<String>>): Unit {
        let ids = info.get("ids") ?? Array<String>()
        deliver(Notification(name: name, ids: ids))
    }

    /** Post with a displayName→id map userInfo (RevocationDashboard). */
    public static func postMap(name: NotificationName, map: HashMap<String, String>): Unit {
        deliver(Notification(name: name, map: map))
    }
}
