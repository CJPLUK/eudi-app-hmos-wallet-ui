/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (Navigation/AppRoute.swift, Navigation/Routable.swift) to Cangjie for the
 * EUDI HarmonyOS wallet.
 *
 * iOS `AppRoute` is a two-level enum: 7 feature route modules wrapping 25
 * leaf cases (AppRoute.swift contains 64 `case` lines in total = 25 leaf
 * declarations + 25 switch arms + 7 wrapper declarations + 7 wrapper switch
 * arms). Each leaf case is mapped below to one snake_case route-name
 * constant; the 7 module wrappers become the grouping comments. Routes with
 * associated values get a companion `*Args` model carrying a `UIConfigType`
 * or the value payload; cross-page delivery uses the `NavArgs` singleton
 * (NavPathInfo.param does not survive push → onReady, syntax_error R-105).
 */
package eudi_logic_ui

import std.collection.HashMap

/**
 * Mirrors Swift `Routable`: anything that can be logged as part of a route
 * transition (`var log: String { get }`).
 */
public interface Routable {
    prop log: String
}

/**
 * Route-name constants — full iOS `AppRoute` case set, one constant per leaf
 * case (snake_case of the iOS `info.key`).
 */
public class AppRoutes {
    // ── FeatureStartupRouteModule ───────────────────────────────────────
    /** iOS: .featureStartupModule(.startup) — key "Startup" */
    public static let startup: String = "startup"

    // ── FeatureCommonRouteModule ────────────────────────────────────────
    /** iOS: .featureCommonModule(.quickPin(config:)) — key "QuickPin" */
    public static let quickPin: String = "quick_pin"
    /** iOS: .featureCommonModule(.qrScanner(config:)) — key "QRScanner" */
    public static let qrScanner: String = "qr_scanner"
    /** iOS: .featureCommonModule(.biometry(config:)) — key "Biometry" */
    public static let biometry: String = "biometry"
    /** iOS: .featureCommonModule(.genericSuccess(config:)) — key "GenericSuccess" */
    public static let genericSuccess: String = "generic_success"

    // ── FeatureDashboardRouteModule ─────────────────────────────────────
    /** iOS: .featureDashboardModule(.dashboard) — key "Dashboard" */
    public static let dashboard: String = "dashboard"
    /** iOS: .featureDashboardModule(.signDocument) — key "SignDocument" */
    public static let signDocument: String = "sign_document"
    /** RQES signing flow entry route (feature eudi_feature_rqes). The dashboard Sign-document
     *  screen pushes this with the picked file path in NavArgs; the flow's remaining routes are
     *  feature-local (RqesRoutes). Value must equal RqesRoutes.documentSelection. */
    public static let rqesDocumentSelection: String = "rqes_document_selection"
    /** iOS: .featureDashboardModule(.sideMenu) — key "SideMenu" */
    public static let sideMenu: String = "side_menu"
    /** iOS: .featureDashboardModule(.settingsMenu) — key "settingsMenu" */
    public static let settingsMenu: String = "settings_menu"
    /** iOS: .featureDashboardModule(.issuanceOption) — key "issuanceOption" */
    public static let issuanceOption: String = "issuance_option"
    /** iOS: .featureDashboardModule(.documentDetails(id:)) — key "DocumentDetails" */
    public static let documentDetails: String = "document_details"
    /** iOS: .featureDashboardModule(.transactionDetails(id:)) — key "TransactionDetails" */
    public static let transactionDetails: String = "transaction_details"

    // ── FeaturePresentationRouteModule ──────────────────────────────────
    /** iOS: .featurePresentationModule(.presentationLoader(...)) — key "PresentationLoader" */
    public static let presentationLoader: String = "presentation_loader"
    /** iOS: .featurePresentationModule(.presentationRequest(...)) — key "PresentationRequest" */
    public static let presentationRequest: String = "presentation_request"
    /** iOS: .featurePresentationModule(.presentationSuccess(config:_:)) — key "PresentationSuccess" */
    public static let presentationSuccess: String = "presentation_success"

    // ── FeatureProximityRouteModule ─────────────────────────────────────
    /** iOS: .featureProximityModule(.proximityConnection(...)) — key "ProximityConnection" */
    public static let proximityConnection: String = "proximity_connection"
    /** iOS: .featureProximityModule(.proximityRequest(...)) — key "ProximityRequest" */
    public static let proximityRequest: String = "proximity_request"
    /** iOS: .featureProximityModule(.proximityLoader(...)) — key "ProximityLoader" */
    public static let proximityLoader: String = "proximity_loader"
    /** iOS: .featureProximityModule(.proximitySuccess(config:_:)) — key "ProximitySuccess" */
    public static let proximitySuccess: String = "proximity_success"

    // ── FeatureIssuanceRouteModule ──────────────────────────────────────
    /** iOS "Add document" chooser (Choose from list / Scan QR) shown before the
     *  issuer catalog. iOS Documents "+" lands here first; OHOS previously jumped
     *  straight to the catalog. */
    public static let addDocumentOptions: String = "add_document_options"
    /** iOS: .featureIssuanceModule(.issuanceAddDocument(config:)) — key "IssuanceAddDocument" */
    public static let issuanceAddDocument: String = "issuance_add_document"
    /** iOS: .featureIssuanceModule(.issuanceSuccess(config:requestItems:)) — key "IssuanceSuccess" */
    public static let issuanceSuccess: String = "issuance_success"
    /** iOS: .featureIssuanceModule(.credentialOfferRequest(config:)) — key "CredentialOfferRequest" */
    public static let credentialOfferRequest: String = "credential_offer_request"
    /** iOS: .featureIssuanceModule(.issuanceCode(config:)) — key "IssuanceCode" */
    public static let issuanceCode: String = "issuance_code"

    // ── FeatureIDPRouteModule ───────────────────────────────────────────
    /** iOS: .featureIDPModule(.requestAuthorization) — key "RequestAuthorization" */
    public static let requestAuthorization: String = "request_authorization"
    /**
     * iOS: .featureIDPModule(.biometry(config:)) — key "Biometry".
     * Same key as the common-module biometry case, hence the same constant
     * (`AppRoutes.biometry`); kept as an alias for per-case traceability.
     */
    public static let idpBiometry: String = AppRoutes.biometry

    /** Every distinct route name (24 — common/IDP biometry share one key). */
    public static func allRoutes(): Array<String> {
        [
            startup,
            quickPin, qrScanner, biometry, genericSuccess,
            dashboard, signDocument, rqesDocumentSelection, sideMenu, settingsMenu,
            issuanceOption, documentDetails, transactionDetails,
            presentationLoader, presentationRequest, presentationSuccess,
            proximityConnection, proximityRequest, proximityLoader, proximitySuccess,
            addDocumentOptions, issuanceAddDocument, issuanceSuccess, credentialOfferRequest, issuanceCode,
            requestAuthorization
        ]
    }
}

// ─── Route parameter models ─────────────────────────────────────────────
// iOS leaf cases with associated values get one model each. Session
// coordinators (RemoteSessionCoordinator / ProximitySessionCoordinator,
// owned by logic-core) are not modelled here; flows hand them over through
// `NavArgs` under the route key.

/** Config payload for quick_pin / qr_scanner / biometry / generic_success / issuance_add_document / credential_offer_request / issuance_code. */
public class RouteConfigArgs <: Routable {
    public let config: UIConfigType

    public init(config: UIConfigType) {
        this.config = config
    }

    public prop log: String {
        get() { "config: ${this.config.log}" }
    }
}

/** Identifier payload for document_details / transaction_details. */
public class RouteIdArgs <: Routable {
    public let id: String

    public init(id: String) {
        this.id = id
    }

    public prop log: String {
        get() { "id: ${this.id}" }
    }
}

/** Payload of presentation_loader / proximity_loader. */
public class RouteLoaderArgs <: Routable {
    public let relyingParty: String
    public let relyingPartyIsTrusted: Bool
    public let originator: String
    public let items: Array<Routable>

    public init(
        relyingParty!: String,
        relyingPartyIsTrusted!: Bool,
        originator!: String,
        items!: Array<Routable> = Array<Routable>()
    ) {
        this.relyingParty = relyingParty
        this.relyingPartyIsTrusted = relyingPartyIsTrusted
        this.originator = originator
        this.items = items
    }

    public prop log: String {
        get() {
            var joined = ""
            for (item in this.items) {
                if (!joined.isEmpty()) {
                    joined += "|"
                }
                joined += item.log
            }
            return "relyingParty: ${this.relyingParty} originator: ${this.originator} items: ${joined}"
        }
    }
}

/** Payload of presentation_request / proximity_request / proximity_connection. */
public class RouteOriginatorArgs <: Routable {
    public let originator: String

    public init(originator: String) {
        this.originator = originator
    }

    public prop log: String {
        get() { "originator: ${this.originator}" }
    }
}

/** Payload of presentation_success / proximity_success / issuance_success. */
public class RouteSuccessArgs <: Routable {
    public let config: UIConfigType
    public let items: Array<Routable>

    public init(config!: UIConfigType, items!: Array<Routable> = Array<Routable>()) {
        this.config = config
        this.items = items
    }

    public prop log: String {
        get() { "config: ${this.config.log}" }
    }
}

/**
 * Cross-page argument channel (syntax_error R-105: `NavPathInfo.param` does
 * not round-trip push → onReady on this binding, so route payloads travel
 * through this process-wide singleton keyed by route name).
 */
public class NavArgs {
    private static let instance: NavArgs = NavArgs()
    private let values: HashMap<String, Any> = HashMap<String, Any>()

    private init() {}

    public static prop shared: NavArgs {
        get() { instance }
    }

    /** Stores the payload for a route; overwrites any previous value. */
    public func set(routeKey: String, value: Any): Unit {
        this.values[routeKey] = value
    }

    /** Reads the payload without consuming it. */
    public func get(routeKey: String): ?Any {
        if (this.values.contains(routeKey)) {
            return this.values[routeKey]
        }
        return None
    }

    /** Reads and removes the payload (single-consumption hand-off). */
    public func take(routeKey: String): ?Any {
        let found = this.get(routeKey)
        this.values.remove(routeKey)
        return found
    }

    /** Drops a stored payload, if any. */
    public func clear(routeKey: String): Unit {
        this.values.remove(routeKey)
    }
}
