/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * eudi_feature_dashboard — EUDI Dashboard feature HAR (Cangjie).
 *
 * Exports: DashboardView, DashboardViewModel, DashboardState, SelectedTab,
 *          selectedTabFromIndex, HomeTabView, DocumentTabView, TransactionTabView,
 *          DashboardInteractor, DashboardNavArgs,
 *          DocumentDetailsView, DocumentDetailsViewModel,
 *          TransactionDetailsView, TransactionDetailsViewModel.
 *
 * Delivers the landing page (3 tabs) with real data: Documents tab lists issued
 * documents (grouped by category) via WalletKitController, History tab lists the
 * transaction log, and tapping a row opens the document / transaction details
 * screen. Empty wallets render the authentic empty state + Add document.
 */
package eudi_feature_dashboard
