/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. eudi_feature_presentation (Cangjie HAR) —
 * the migrated iOS feature-presentation module: the online (OpenID4VP) data-
 * sharing flow. A relying party's presentation request is received over a
 * RemoteSessionCoordinator (logic-core), its requested claims are surfaced for
 * user selection on the shared Request screen (feature-common BaseRequestView),
 * the user confirms, and the disclosed items are sent back through the
 * coordinator; a state-stream subscription drives the loading→success transition.
 *
 * Public surface (consumed by the app shell / composition root):
 *   - Views:        PresentationRequestView, PresentationLoaderView,
 *                   PresentationSuccessView
 *   - ViewModels:   PresentationRequestViewModel, PresentationLoaderViewModel,
 *                   PresentationSuccessViewModel
 *   - Interactor:   PresentationInteractor(Impl)
 *
 * The module package marker. All feature types live in sibling .cj files
 * (presentation_interactor.cj, presentation_view_models.cj,
 * presentation_views.cj).
 */
package eudi_feature_presentation
