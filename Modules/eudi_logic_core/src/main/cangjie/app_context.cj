/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * Holds the UIAbilityContext handed in from the ETS EntryAbility across the
 * CJHybridComponent bridge (entry/index.cj `setAbilityContext`).
 *
 * Why this exists: the wallet engine persists issued credentials in an encrypted
 * RDB store, and `relational_store.getRdbStore` requires a real UIAbilityContext.
 * This app is ETS-hosted (ArkTS EntryAbility loads the Cangjie AppRoot via
 * CJHybridComponent), so the Cangjie side has no UIAbility of its own and cannot
 * obtain the context by itself (`getContext()` is only a test-runner global).
 * The ETS layer therefore passes its context down once at startup; WalletKitImpl
 * reads it here to build the persistent DataStorageService.
 */
package eudi_logic_core

import ohos.app.ability.ui_ability.UIAbilityContext

/** Process-wide holder for the ability context (set once at app startup). */
public class AppContextHolder {
    private static var ctx: ?UIAbilityContext = None

    /** Called from the ETS bridge before the wallet graph is assembled. */
    public static func set(c: UIAbilityContext): Unit {
        ctx = Some(c)
    }

    /** The ability context, or None if the bridge has not run yet (the wallet
     *  then falls back to in-memory storage so the app still starts). */
    public static func get(): ?UIAbilityContext {
        ctx
    }
}
