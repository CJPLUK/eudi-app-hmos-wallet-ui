/*
 * rqes_routes.cj — the RQES flow's NavPathStack route names.
 *
 * iOS EudiRQESUi owns an internal RouterGraph with its own Route enum; HarmonyOS routes
 * through the app's central NavPathStack, so each screen is a route string registered in
 * entry/app_page_map.cj. These live in the feature (not eudi_logic_ui.AppRoutes) to keep the
 * module self-contained and standalone-compilable; app_page_map references them directly.
 * The dashboard entry pushes `documentSelection` to start the flow — see task card §3.
 */
package eudi_feature_rqes

public class RqesRoutes {
    public static let documentSelection: String = "rqes_document_selection"
    public static let serviceSelection: String = "rqes_service_selection"
    public static let credentialSelection: String = "rqes_credential_selection"
    public static let signedDocument: String = "rqes_signed_document"
    public static let documentViewer: String = "rqes_document_viewer"
}
