/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Worker/{ReIssuanceWorkManager,RevocationWorkManager}.swift.
 *
 * iOS uses a detached `Task` loop with `Task.sleep` and posts to NotificationCenter.
 * Cangjie has no structured concurrency Task; the periodic loop runs on a spawned
 * thread guarded by a stop flag, and NotificationCenter posts become calls into a
 * lightweight in-process NotificationCenter (notifications.cj).
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, AtomicBool}
import std.time.*
import eudi_logic_business.StringUtil
import eudi_logic_business.DateUtil

// ─────────────────────────────────────────────────────────────────────────────
// Worker/ReIssuanceWorkManager.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol ReIssuanceWorkManager: Sendable`. */
public interface ReIssuanceWorkManager {
    func start(): Unit
    func stop(): Unit
}

/** Mirrors iOS `final actor ReIssuanceWorkManagerImpl`. */
public class ReIssuanceWorkManagerImpl <: ReIssuanceWorkManager {
    private let reIssuanceRule: ReIssuanceRule
    private let walletKitController: WalletKitController
    private let initialDelaySeconds: Int64 = 30
    private let lock = Mutex()
    private var isRunning = AtomicBool(false)
    private var started = false

    public init(configLogic!: WalletKitConfig, walletKitController!: WalletKitController) {
        this.reIssuanceRule = configLogic.documentIssuanceConfig.reIssuanceRule
        this.walletKitController = walletKitController
    }

    public func start(): Unit {
        synchronized(lock) {
            if (this.started) { return }
            this.started = true
        }
        this.isRunning.store(true)
        let self0 = this
        spawn {
            sleepSeconds(self0.initialDelaySeconds)
            while (self0.isRunning.load()) {
                try {
                    self0.checkReIssuance()
                } catch (_: Exception) {}
                sleepSeconds(DateUtil.intervalSeconds(self0.reIssuanceRule.backgroundIntervalSeconds))
            }
        }
    }

    public func stop(): Unit {
        this.isRunning.store(false)
        synchronized(lock) { this.started = false }
    }

    private func checkReIssuance(): Unit {
        let issuedDocuments = ArrayList<DocClaimsDecodable>()
        for (d in this.walletKitController.fetchIssuedDocuments()) {
            let remainingUsage = remainingOrDefault(d, -1)
            let belowMinCount = remainingUsage <= this.reIssuanceRule.minNumberOfCredentials
            let hasOneTimeUsePolicy = d.credentialPolicy == CredentialPolicy.oneTimeUse
            let expiresWithinThreshold = expiresWithinHours(d, this.reIssuanceRule.minExpirationHours)
            if ((belowMinCount && hasOneTimeUsePolicy) || expiresWithinThreshold) {
                issuedDocuments.add(d)
            }
        }
        if (issuedDocuments.size == 0) { return }

        let succeed = ArrayList<String>()
        let failed = ArrayList<String>()
        let removedIds = ArrayList<String>()

        for (document in issuedDocuments) {
            try {
                let newDocument = this.walletKitController.reIssueDocument(identifier: document.id, isBackgroundOperation: true)
                removedIds.add(document.id)
                succeed.add(newDocument.id)
            } catch (_: Exception) {
                failed.add(document.id)
            }

            try { this.walletKitController.removeAllFailedReIssuedDocuments() } catch (_: Exception) {}

            if (failed.size > 0) {
                try { this.walletKitController.storeFailedReIssuedDocuments(failed.toArray()) } catch (_: Exception) {}
            }

            if (succeed.size > 0) {
                notifyDocumentsList()
                notifyDocumentDetails(removedIds.toArray())
            }
        }
    }

    private func notifyDocumentDetails(removedIds: Array<String>): Unit {
        let info = HashMap<String, Array<String>>()
        info.add("ids", removedIds)
        NotificationCenter.postIds(NotificationName.ReIssuanceDetailsRefresh, info)
    }

    private func notifyDocumentsList(): Unit {
        NotificationCenter.post(NotificationName.DocumentTabRefresh)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Worker/RevocationWorkManager.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol RevocationWorkManager: Sendable`. */
public interface RevocationWorkManager {
    func start(): Unit
    func stop(): Unit
}

/** Mirrors iOS `final actor RevocationWorkManagerImpl`. */
public class RevocationWorkManagerImpl <: RevocationWorkManager {
    private let configLogic: WalletKitConfig
    private let walletKitController: WalletKitController
    private let initialDelaySeconds: Int64 = 30
    private let lock = Mutex()
    private var isRunning = AtomicBool(false)
    private var started = false

    public init(configLogic!: WalletKitConfig, walletKitController!: WalletKitController) {
        this.configLogic = configLogic
        this.walletKitController = walletKitController
    }

    public func start(): Unit {
        synchronized(lock) {
            if (this.started) { return }
            this.started = true
        }
        this.isRunning.store(true)
        let self0 = this
        spawn {
            sleepSeconds(self0.initialDelaySeconds)
            while (self0.isRunning.load()) {
                try {
                    self0.checkRevocation()
                } catch (_: Exception) {}
                sleepSeconds(DateUtil.intervalSeconds(self0.configLogic.revocationIntervalSeconds))
            }
        }
    }

    public func stop(): Unit {
        this.isRunning.store(false)
        synchronized(lock) { this.started = false }
    }

    private func checkRevocation(): Unit {
        let issuedDocuments = this.walletKitController.fetchIssuedDocuments()
        var revokedStoredDocuments: Array<String>
        try {
            revokedStoredDocuments = this.walletKitController.fetchRevokedDocuments()
        } catch (_: Exception) {
            revokedStoredDocuments = Array<String>()
        }

        let revokedDocuments = HashMap<String, String>()   // displayName -> id
        let fromRevokedToValid = ArrayList<String>()

        for (document in issuedDocuments) {
            match (document.statusIdentifier) {
                case None => continue
                case Some(identifier) =>
                    let status = this.walletKitController.getDocumentStatus(identifier)
                    let isInRevokedStorage = containsValue(revokedStoredDocuments, document.id)
                    match (status) {
                        case invalid => if (!isInRevokedStorage) { revokedDocuments.add(document.displayName ?? "", document.id) }
                        case suspended => if (!isInRevokedStorage) { revokedDocuments.add(document.displayName ?? "", document.id) }
                        case valid => if (isInRevokedStorage) { fromRevokedToValid.add(document.id) }
                        case _ => continue
                    }
            }
        }

        if (fromRevokedToValid.size > 0) {
            try { removeRevokedDocuments(fromRevokedToValid.toArray()) } catch (_: Exception) {}
        }

        if (revokedDocuments.size > 0) {
            let ids = ArrayList<String>()
            for ((_, v) in revokedDocuments) { ids.add(v) }
            try { this.walletKitController.storeRevokedDocuments(ids.toArray()) } catch (_: Exception) {}
            notifyListeners(revokedDocuments)
        }

        if (fromRevokedToValid.size > 0 || revokedDocuments.size > 0) {
            notifyDocumentTabListener()
        }
    }

    private func removeRevokedDocuments(ids: Array<String>): Unit {
        for (id in ids) {
            this.walletKitController.removeRevokedDocument(id)
        }
    }

    private func notifyListeners(revoked: HashMap<String, String>): Unit {
        NotificationCenter.postMap(NotificationName.RevocationDashboard, revoked)
        let ids = ArrayList<String>()
        for ((_, v) in revoked) { ids.add(v) }
        let info = HashMap<String, Array<String>>()
        info.add("ids", ids.toArray())
        NotificationCenter.postIds(NotificationName.DocumentDetailsRefresh, info)
    }

    private func notifyDocumentTabListener(): Unit {
        NotificationCenter.post(NotificationName.DocumentTabRefresh)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// shared worker helpers
// ─────────────────────────────────────────────────────────────────────────────

func remainingOrDefault(doc: DocClaimsDecodable, fallback: Int64): Int64 {
    match (doc.credentialsUsageCounts) {
        case Some(c) => c.remaining
        case None => fallback
    }
}

func expiresWithinHours(doc: DocClaimsDecodable, hours: Int64): Bool {
    match (doc.validUntil) {
        case Some(d) => DateUtil.isWithinNextHours(d, hours)
        case None => false
    }
}

func containsValue(arr: Array<String>, value: String): Bool {
    for (s in arr) {
        if (s == value) { return true }
    }
    return false
}

func sleepSeconds(seconds: Int64): Unit {
    if (seconds <= 0) { return }
    sleep(seconds * Duration.second)
}
