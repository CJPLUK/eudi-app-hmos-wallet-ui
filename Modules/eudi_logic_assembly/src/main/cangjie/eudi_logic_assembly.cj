/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * eudi_logic_assembly — EUDI composition root (Cangjie HAR).
 *
 * Ported from the iOS logic-assembly module:
 *   - LogicAssembly.swift              (the @_exported umbrella of every logic +
 *                                       feature module — represented here by the
 *                                       module dependency set in cjpm.toml)
 *   - DI/LogicAssemblyModule.swift     (Swinject Assembly registering RouterHost)
 *   - Extension/DIGraph+Extensions.swift
 *                                      (assembleDependenciesGraph — wires the
 *                                       logic-core object graph)
 *
 * iOS assembles its dependency graph with Swinject (inversion of control). The
 * delivered HarmonyOS app uses manual constructor injection (entry/app_composition.cj),
 * which is the same dependency-inversion contract without a reflective container.
 * This module owns the *UI-independent* half of that graph — the wallet-kit object
 * graph (logic-core + logic-storage + logic-api) — as a reusable `LogicAssembly`,
 * so the entry composition root delegates the wallet wiring here instead of
 * duplicating LogicCoreAssembly assembly inline. The RouterHost half stays in the
 * entry because it is bound to the ArkUI NavPathStack (iOS binds RouterHostImpl to
 * the SwiftUI navigation path the same way), so it cannot be assembled UI-free.
 */
package eudi_logic_assembly

import eudi_logic_business.{ConfigLogic, PrefsController}
import eudi_logic_core.{WalletKitController, LogicCoreAssembly}
import eudi_logic_storage.{
    createStorageConfig,
    createBookmarkStorageController,
    createTransactionLogStorageController,
    createRevokedDocumentStorageController,
    createFailedReIssuedDocStorageController
}
import eudi_logic_api.{makeNetworkSessionProvider, makeDefaultWalletAttestationRepository}

/**
 * The UI-independent composition root. Mirrors the wallet-graph portion of iOS
 * `DIGraph.assembleDependenciesGraph()`: assembles logic-core over its storage +
 * api collaborators and resolves the shared WalletKitController.
 *
 * Constructed once with the app's ConfigLogic; `resolveWalletController()` returns
 * the fully-wired engine facade consumed by every feature interactor.
 */
public class LogicAssembly {
    private let configLogic: ConfigLogic
    private let prefsController: PrefsController

    public init(configLogic!: ConfigLogic, prefsController!: PrefsController) {
        this.configLogic = configLogic
        this.prefsController = prefsController
    }

    /**
     * Assembles the logic-core object graph (mirrors iOS LogicCoreAssembly + its
     * sibling storage/api assemblies) and resolves the WalletKitController. This
     * is the exact wiring the entry composition root used inline; centralising it
     * here keeps the DI graph in one place (iOS DIGraph+Extensions parity).
     */
    public func resolveWalletController(): WalletKitController {
        let storageConfig = createStorageConfig()
        let assembly = LogicCoreAssembly(
            this.configLogic,
            this.prefsController,
            storageConfig.storageDir,
            createBookmarkStorageController(storageConfig),
            createTransactionLogStorageController(storageConfig),
            createRevokedDocumentStorageController(storageConfig),
            createFailedReIssuedDocStorageController(storageConfig),
            makeDefaultWalletAttestationRepository(),
            makeNetworkSessionProvider()
        )
        return assembly.resolveWalletKitController()
    }
}
