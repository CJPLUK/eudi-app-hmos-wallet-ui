/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. eudi_feature_proximity (Cangjie HAR) —
 * the migrated iOS feature-proximity module: the in-person (ISO 18013-5 BLE)
 * data-sharing flow. The wallet shows a QR engagement code, a reader connects
 * over BLE, sends a presentation request whose claims are surfaced for user
 * selection (shared feature-common BaseRequestView), the user confirms and the
 * disclosed items are sent back over the ProximitySessionCoordinator.
 *
 * Public surface (consumed by the app shell / composition root):
 *   - Views:        ProximityConnectionView, ProximityRequestView,
 *                   ProximityLoaderView, ProximitySuccessView
 *   - ViewModels:   ProximityConnectionViewModel, ProximityRequestViewModel,
 *                   ProximityLoaderViewModel, ProximitySuccessViewModel
 *   - Interactor:   ProximityInteractor(Impl)
 *
 * The QR engagement + BLE transfer are driven by the real wallet-kit BLE
 * presentation service (logic-core startProximityPresentation → beginPresentation
 * (PresentationFlow.ble)); the device-engagement payload ("mdoc:" +
 * base64url(CBOR)) comes from the coordinator's startQrEngagement and is
 * rendered by the ArkUI QRCode component. When the device/engine reports BLE
 * unavailable the screen shows the iOS "capability unavailable" error rather
 * than faking success.
 *
 * The module package marker. All feature types live in sibling .cj files
 * (proximity_interactor.cj, proximity_view_models.cj, proximity_views.cj).
 */
package eudi_feature_proximity
