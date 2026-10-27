/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Error/RuntimeError.swift) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * Swift `RuntimeError: LocalizedError` becomes a Cangjie enum exposing
 * `localizedDescription`. The generic case resolves its message through the
 * delivered eudi_logic_resources localization manager, exactly like the iOS
 * source resolves `LocalizableStringKey.genericErrorDesc`.
 */
package eudi_logic_business

import eudi_logic_resources.LocalizableManager
import eudi_logic_resources.LocalizableStringKey

/**
 * Unified error type of the wallet business layer.
 * Mirrors iOS `RuntimeError` (customError / genericError).
 */
public enum RuntimeError <: ToString {
    | customError(String)
    | genericError

    /** Mirrors Swift `errorDescription`. */
    public prop localizedDescription: String {
        get() {
            match (this) {
                case customError(message) => message
                case genericError => LocalizableManager.get(LocalizableStringKey.genericErrorDesc)
            }
        }
    }

    public func toString(): String {
        return this.localizedDescription
    }
}
