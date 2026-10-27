/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 *
 * Ported from the iOS logic-ui module (Sources/Controller/DeepLinkController.swift)
 * to Cangjie for the EUDI HarmonyOS wallet.
 *
 * The iOS controller mixes a pure, testable decision core (which action a URL
 * maps to, whether to cache vs. navigate, which route to push) with iOS-only
 * side effects: `UIApplication.open`, `NotificationCenter.post`,
 * `EudiRQESUi.instance().resume`, and `fatalError` when a coordinator is nil.
 * Those effects have no HAR counterpart and, more importantly, are exactly the
 * parts the iOS unit tests could not assert directly (they verify router.push /
 * prefs.remove instead). This port keeps the decision core 1:1 and records the
 * chosen branch as a `DeepLinkOutcome` value plus the real RouterHost
 * push/popTo calls, so every iOS assertion has a Cangjie equivalent. The
 * coordinator-nil case is a non-crashing `MissingCoordinator` outcome instead
 * of `fatalError` (iOS behaviour is unreachable-by-contract; we make it
 * assertable rather than aborting the process).
 */
package eudi_logic_ui

import std.collection.ArrayList
import eudi_logic_business.{PrefsController, PrefsKey, ParsedUrl, UrlUtil}

/**
 * Mirrors iOS `DeepLink.Action` (the `String`-raw enum). `name` mirrors the
 * iOS private `name` computed property (rawValue with `_` → `-`) used to look
 * up the registered schemas for the action.
 */
public enum DeepLinkAction <: Equatable<DeepLinkAction> & ToString {
    | Openid4vp
    | CredentialOffer
    | HaipVci
    | HaipVp
    | Rqes
    | External

    /** iOS `rawValue`. */
    public prop rawValue: String {
        get() {
            match (this) {
                case Openid4vp => "openid4vp"
                case CredentialOffer => "credential_offer"
                case HaipVci => "haip_vci"
                case HaipVp => "haip_vp"
                case Rqes => "rqes"
                case External => "external"
            }
        }
    }

    /** iOS private `name`: rawValue with underscores turned into hyphens. */
    public prop name: String {
        get() { this.rawValue.replace("_", "-") }
    }

    public func toString(): String {
        return this.rawValue
    }

    public operator func ==(other: DeepLinkAction): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: DeepLinkAction): Bool {
        return !(this == other)
    }

    private func schemas(urlSchemaController: UrlSchemaController): Array<String> {
        return urlSchemaController.retrieveSchemas(this.name)
    }

    /**
     * iOS `parseType(with:and:)`: the scheme is matched against each action's
     * registered schema list. openid4vp/haip_vp collapse to `Openid4vp`;
     * credential_offer/haip_vci collapse to `CredentialOffer`; rqes stays
     * `Rqes`; anything unmatched defaults to `External` (iOS never returns nil
     * from this — the `default` arm returns `.external`).
     */
    public static func parseType(scheme: String, urlSchemaController: UrlSchemaController): DeepLinkAction {
        if (contains(Openid4vp.schemas(urlSchemaController), scheme)
            || contains(HaipVp.schemas(urlSchemaController), scheme)) {
            return Openid4vp
        }
        if (contains(CredentialOffer.schemas(urlSchemaController), scheme)
            || contains(HaipVci.schemas(urlSchemaController), scheme)) {
            return CredentialOffer
        }
        if (contains(Rqes.schemas(urlSchemaController), scheme)) {
            return Rqes
        }
        return External
    }

    private static func contains(list: Array<String>, value: String): Bool {
        for (entry in list) {
            if (entry == value) {
                return true
            }
        }
        return false
    }
}

/**
 * Mirrors iOS `UrlSchemaController` (iOS reads the app `Info.plist`
 * CFBundleURLSchemes). A HAR has no Info.plist, so production supplies the
 * registered schemas explicitly; tests inject a fake map. `retrieveSchemas`
 * takes the hyphenated action `name` and returns the schemes registered for it.
 */
public interface UrlSchemaController {
    /** iOS `retrieveSchemas(with:)`. */
    func retrieveSchemas(name: String): Array<String>
}

/**
 * Default implementation backed by an explicit name → schemas map. The
 * composition root builds this from the bundle's declared deep-link schemes;
 * an unknown name returns an empty list (matching iOS returning `[]` when the
 * key is absent from Info.plist, which then falls through to `.external`).
 */
public class DefaultUrlSchemaController <: UrlSchemaController {
    private let mapping: ArrayList<(String, Array<String>)>

    public init() {
        this.mapping = ArrayList<(String, Array<String>)>()
    }

    public init(mapping: Array<(String, Array<String>)>) {
        this.mapping = ArrayList<(String, Array<String>)>(mapping)
    }

    /** Registers/overrides the schemas for one action name. */
    public func register(name: String, schemas: Array<String>): Unit {
        var i: Int64 = 0
        while (i < this.mapping.size) {
            if (this.mapping[i][0] == name) {
                this.mapping[i] = (name, schemas)
                return
            }
            i++
        }
        this.mapping.add((name, schemas))
    }

    public func retrieveSchemas(name: String): Array<String> {
        for ((key, value) in this.mapping) {
            if (key == name) {
                return value
            }
        }
        return Array<String>()
    }
}

/**
 * Mirrors iOS `DeepLink.Executable`. `link` is the parsed URL (iOS
 * `URLComponents`); `plainUrl` is the original absolute string (iOS `URL`);
 * `action` is the resolved deep-link action. `requiresCoordinator` mirrors the
 * iOS computed property (true only for `openid4vp`).
 */
public class DeepLinkExecutable <: Equatable<DeepLinkExecutable> {
    public let link: ParsedUrl
    public let plainUrl: String
    public let action: DeepLinkAction

    public init(link: ParsedUrl, plainUrl: String, action: DeepLinkAction) {
        this.link = link
        this.plainUrl = plainUrl
        this.action = action
    }

    /** iOS `requiresCoordinator`: only OpenId4VP needs a session coordinator. */
    public prop requiresCoordinator: Bool {
        get() { this.action == DeepLinkAction.Openid4vp }
    }

    /**
     * The `code` query item (iOS `link.queryItems?.first { $0.name == "code" }`),
     * used by the rqes flow. `ParsedUrl.query` is the raw query string, so we
     * split it into `key=value` pairs and pick `code`. Returns None when there
     * is no `code` item.
     */
    public prop code: ?String {
        get() { firstQueryValue("code") }
    }

    /** Reads the first value of a query item by key from the parsed URL. */
    public func firstQueryValue(key: String): ?String {
        let raw: String
        match (this.link.query) {
            case Some(q) => raw = q
            case None => return None
        }
        for (pair in raw.split("&")) {
            if (pair.isEmpty()) {
                continue
            }
            let name: String
            let value: String
            match (pair.indexOf("=")) {
                case Some(idx) =>
                    name = pair[0..idx]
                    value = pair[(idx + 1)..pair.size]
                case None =>
                    name = pair
                    value = ""
            }
            if (name == key) {
                return value
            }
        }
        return None
    }

    /**
     * Structural equality (iOS `Executable: Equatable`). Two executables are
     * equal when their action, plain URL and parsed scheme match — enough to
     * back the iOS `XCTAssertEqual(action, expected)` deep-link assertions.
     */
    public operator func ==(other: DeepLinkExecutable): Bool {
        return this.action == other.action
            && this.plainUrl == other.plainUrl
            && optEq(this.link.scheme, other.link.scheme)
    }

    public operator func !=(other: DeepLinkExecutable): Bool {
        return !(this == other)
    }

    private static func optEq(a: ?String, b: ?String): Bool {
        match ((a, b)) {
            case (Some(x), Some(y)) => x == y
            case (None, None) => true
            case _ => false
        }
    }
}

/**
 * The branch `handleDeepLinkAction` took. iOS performs an opaque side effect
 * per branch (open URL / post notification / push route / resume RQES / cache);
 * this enum records which branch ran so tests can assert the decision the same
 * way the iOS tests assert router.push / prefs.remove.
 */
public enum DeepLinkOutcome <: Equatable<DeepLinkOutcome> & ToString {
    /** No action was handled (e.g. controller freshly constructed). */
    | NoAction
    /** Pre-auth: URL cached, no navigation (iOS cache-only branch). */
    | Cached
    /** Pre-auth rqes while logged in with documents: cache + popTo(dashboard). */
    | CachedAndPoppedToDashboard
    /** openid4vp/haip_vp, not foreground → pushed the presentation route. */
    | PushedPresentation
    /** openid4vp/haip_vp already foreground → iOS posts a notification (no push). */
    | PresentationAlreadyForeground
    /** openid4vp/haip_vp with no coordinator → iOS fatalErrors; here: no push. */
    | MissingCoordinator
    /** credential_offer/haip_vci, not foreground → pushed the issuance route. */
    | PushedIssuance
    /** credential_offer/haip_vci already foreground → iOS posts a notification. */
    | IssuanceAlreadyForeground
    /** external → iOS opens the URL in the system browser. */
    | ExternalOpen
    /** rqes with a `code` → iOS schedules EudiRQESUi.resume with that code. */
    | RqesResume(String)
    /** rqes without a `code` → iOS early-returns after removing the cache. */
    | RqesNoCode

    public func toString(): String {
        match (this) {
            case NoAction => "NoAction"
            case Cached => "Cached"
            case CachedAndPoppedToDashboard => "CachedAndPoppedToDashboard"
            case PushedPresentation => "PushedPresentation"
            case PresentationAlreadyForeground => "PresentationAlreadyForeground"
            case MissingCoordinator => "MissingCoordinator"
            case PushedIssuance => "PushedIssuance"
            case IssuanceAlreadyForeground => "IssuanceAlreadyForeground"
            case ExternalOpen => "ExternalOpen"
            case RqesResume(code) => "RqesResume(${code})"
            case RqesNoCode => "RqesNoCode"
        }
    }

    public operator func ==(other: DeepLinkOutcome): Bool {
        match ((this, other)) {
            case (RqesResume(a), RqesResume(b)) => a == b
            case _ => this.toString() == other.toString()
        }
    }

    public operator func !=(other: DeepLinkOutcome): Bool {
        return !(this == other)
    }
}

/**
 * Mirrors iOS `DeepLinkController`. `handleDeepLinkAction` drops the iOS
 * `remoteSessionCoordinator` object (a logic-core type) in favour of a
 * `hasCoordinator` flag, because the only thing the decision core needs from it
 * is presence/absence (openid4vp requires one). The concrete route object the
 * coordinator would carry is a composition-root concern.
 */
public interface DeepLinkController {
    /** iOS `hasDeepLink(url:)`. */
    func hasDeepLink(url: String): ?DeepLinkExecutable
    /** iOS `getPendingDeepLinkAction()`. */
    func getPendingDeepLinkAction(): ?DeepLinkExecutable
    /** iOS `cacheDeepLinkURL(url:)`. */
    func cacheDeepLinkURL(url: String): Unit
    /** iOS `removeCachedDeepLinkURL()`. */
    func removeCachedDeepLinkURL(): Unit
    /** iOS `handleDeepLinkAction(routerHost:deepLinkExecutable:remoteSessionCoordinator:)`. */
    func handleDeepLinkAction(
        routerHost: RouterHost,
        deepLinkExecutable: DeepLinkExecutable,
        hasCoordinator: Bool
    ): DeepLinkOutcome
}

public class DeepLinkControllerImpl <: DeepLinkController {
    private let prefsController: PrefsController
    private let urlSchemaController: UrlSchemaController
    /** Last branch taken, for observers/tests (iOS relies on side effects). */
    private var lastOutcomeValue: DeepLinkOutcome = DeepLinkOutcome.NoAction

    public init(prefsController: PrefsController, urlSchemaController: UrlSchemaController) {
        this.prefsController = prefsController
        this.urlSchemaController = urlSchemaController
    }

    /** The outcome of the most recent `handleDeepLinkAction`. */
    public prop lastOutcome: DeepLinkOutcome {
        get() { this.lastOutcomeValue }
    }

    public func getPendingDeepLinkAction(): ?DeepLinkExecutable {
        match (this.prefsController.getString(PrefsKey.cachedDeepLink)) {
            case Some(cached) =>
                match (UrlUtil.toCompatibleUrl(cached)) {
                    case Some(_) => return this.hasDeepLink(cached)
                    case None => return None
                }
            case None => return None
        }
    }

    public func hasDeepLink(url: String): ?DeepLinkExecutable {
        // iOS builds URLComponents(url:resolvingAgainstBaseURL:) and reads the
        // scheme. UrlUtil.parse returns None (→ nil) for malformed URLs and for
        // URLs without a scheme, matching the iOS guard.
        match (UrlUtil.parse(url)) {
            case Some(parsed) =>
                match (parsed.scheme) {
                    case Some(scheme) =>
                        let action = DeepLinkAction.parseType(scheme, this.urlSchemaController)
                        return DeepLinkExecutable(parsed, url, action)
                    case None => return None
                }
            case None => return None
        }
    }

    public func handleDeepLinkAction(
        routerHost: RouterHost,
        deepLinkExecutable: DeepLinkExecutable,
        hasCoordinator: Bool
    ): DeepLinkOutcome {
        let action = deepLinkExecutable.action

        // iOS local computed vars, evaluated against the router each read.
        let isVciExecutable =
            action == DeepLinkAction.CredentialOffer && routerHost.userIsLoggedInWithNoDocuments()
        let isRqesPendingAction =
            action == DeepLinkAction.Rqes && !routerHost.isScreenForeground(AppRoutes.dashboard)
        let shouldPopToDashboardFirst =
            routerHost.userIsLoggedInWithDocuments() && isRqesPendingAction

        // iOS guard: continue to post-auth only when NOT popping-to-dashboard
        // first AND (logged in with documents OR a VCI-with-no-docs case).
        let proceedPostAuth =
            !shouldPopToDashboardFirst && (routerHost.userIsLoggedInWithDocuments() || isVciExecutable)

        if (!proceedPostAuth) {
            // Pre-auth branch: cache the (parsed) URL, optionally popTo dashboard.
            match (this.rebuildUrl(deepLinkExecutable)) {
                case Some(url) => this.cacheDeepLinkURL(url)
                case None => ()
            }
            if (shouldPopToDashboardFirst) {
                routerHost.popTo(AppRoutes.dashboard, false)
                return this.record(DeepLinkOutcome.CachedAndPoppedToDashboard)
            }
            return this.record(DeepLinkOutcome.Cached)
        }

        this.removeCachedDeepLinkURL()

        match (action) {
            case Openid4vp | HaipVp =>
                if (!hasCoordinator) {
                    // iOS: fatalError. Here: assertable no-op.
                    return this.record(DeepLinkOutcome.MissingCoordinator)
                }
                if (!routerHost.isScreenForeground(AppRoutes.presentationRequest)) {
                    routerHost.push(AppRoutes.presentationRequest)
                    return this.record(DeepLinkOutcome.PushedPresentation)
                }
                return this.record(DeepLinkOutcome.PresentationAlreadyForeground)
            case External =>
                // iOS: deepLinkExecutable.plainUrl.open() — system browser.
                return this.record(DeepLinkOutcome.ExternalOpen)
            case CredentialOffer | HaipVci =>
                if (!routerHost.isScreenForeground(AppRoutes.credentialOfferRequest)) {
                    routerHost.push(AppRoutes.credentialOfferRequest)
                    return this.record(DeepLinkOutcome.PushedIssuance)
                }
                return this.record(DeepLinkOutcome.IssuanceAlreadyForeground)
            case Rqes =>
                match (deepLinkExecutable.code) {
                    case Some(code) => return this.record(DeepLinkOutcome.RqesResume(code))
                    case None => return this.record(DeepLinkOutcome.RqesNoCode)
                }
        }
    }

    public func cacheDeepLinkURL(url: String): Unit {
        this.prefsController.setValue(url, PrefsKey.cachedDeepLink)
    }

    public func removeCachedDeepLinkURL(): Unit {
        this.prefsController.remove(PrefsKey.cachedDeepLink)
    }

    private func record(outcome: DeepLinkOutcome): DeepLinkOutcome {
        this.lastOutcomeValue = outcome
        return outcome
    }

    /**
     * iOS caches `deepLinkExecutable.link.url` (the URLComponents' resolved
     * URL). ParsedUrl has no round-tripping `url` accessor, so we cache the
     * original plain URL, which is the same string the components were built
     * from. Returns None only if the plain URL is empty.
     */
    private func rebuildUrl(deepLinkExecutable: DeepLinkExecutable): ?String {
        if (deepLinkExecutable.plainUrl.isEmpty()) {
            return None
        }
        return deepLinkExecutable.plainUrl
    }
}

/** Factory replacing the iOS Swinject assembly registration for DeepLinkController. */
public func createDeepLinkController(
    prefsController: PrefsController,
    urlSchemaController: UrlSchemaController
): DeepLinkController {
    return DeepLinkControllerImpl(prefsController, urlSchemaController)
}
