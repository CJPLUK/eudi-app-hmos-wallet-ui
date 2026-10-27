/*
 * rqes_coordinator.cj — ports the navigation half of eudi-lib-ios-rqes-ui
 * Sources/Presentation/Router/RouterGraph.swift (nextView(for:) + navigateTo).
 *
 * iOS presents a fresh ContainerViewController per state modally; HarmonyOS pushes the
 * matching route onto the central NavPathStack. `rqesRouteForState` is the 1:1 map of
 * iOS `nextView(for state)`; `rqesResume` is the deep-link continuation (facade.resume then
 * push the route for the new state), invoked from the app's RqesResume(code) deep-link seam.
 */
package eudi_feature_rqes

import eudi_logic_ui.RouterHost
import ohos_app_cangjie_eudi_cjrqes_ui.{EudiRQESUi, RqesUiState, EudiRQESUiError}

// iOS RouterGraph.nextView(for:): .initial/.credentials → DocumentSelection, .rssps → Service,
// .sign → SignedDocument, .view → DocumentViewer. .none is invalid (throws).
public func rqesRouteForState(state: RqesUiState): String {
    return match (state) {
        case initial => RqesRoutes.documentSelection
        case credentials => RqesRoutes.documentSelection
        case rssps => RqesRoutes.serviceSelection
        case sign => RqesRoutes.signedDocument
        case view => RqesRoutes.documentViewer
        case none => throw EudiRQESUiError.invalidState("none")
    }
}

// Deep-link continuation. iOS: EudiRQESUi.resume(authorizationCode:) advances the state and
// re-presents; here we advance the facade state then push the route for the new state.
// Called from the app deep-link seam when it decides RqesResume(code).
//
// iOS wraps this in `try?` (DeepLinkController .rqes): a cold start delivering
// rqes://…?code has no registered EudiRQESUi (and no signing session to resume),
// so the resume is silently dropped rather than crashing.
public func rqesResume(code: String, router: RouterHost): Unit {
    try {
        let facade = EudiRQESUi.instance()
        facade.resume(code)
        router.push(rqesRouteForState(facade.getState()))
    } catch (_: Exception) {
        ()
    }
}
