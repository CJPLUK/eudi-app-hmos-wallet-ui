/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. eudi_feature_issuance (Cangjie HAR) —
 * the migrated iOS feature-issuance module: Add-Document, Credential-Offer,
 * Transaction-Code and issuance-success flows, plus the in-app Web-component
 * browser-authorization path that completes auth-code (eudiw PID) issuance.
 *
 * Public surface (consumed by the app shell / composition root):
 *   - Views:        AddDocumentView, DocumentOfferView, OfferCodeView
 *   - ViewModels:   AddDocumentViewModel, DocumentOfferViewModel, OfferCodeViewModel
 *   - Interactors:  AddDocumentInteractor(Impl), DocumentOfferInteractor(Impl)
 *
 * The module package marker. All feature types live in sibling .cj files
 * (issuance_interactor.cj, issuance_view_models.cj, add_document_view.cj,
 * document_offer_view.cj).
 */
package eudi_feature_issuance
