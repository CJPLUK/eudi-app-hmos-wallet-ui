/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Config/ConfigLogic.swift, KeyChainConfig.swift,
 * ConfigLogic+Extensions.swift) to Cangjie.
 *
 * iOS reads build type / variant / version from the app bundle Info.plist; a
 * HarmonyOS logic HAR has no bundle dictionary, so `ConfigLogicImpl` takes the
 * same values as constructor parameters with the iOS fallback defaults
 * (RELEASE-fallback handled by the caller passing nothing: this skeleton app is
 * built as DEBUG/DEV per the module contract). The `rqesConfig` member depends
 * on the external EudiRQESUi SDK and is out of this module's migration scope.
 *
 * The app version itself lives in the HarmonyOS bundle, which only `entry` can
 * read; it reaches this module through `AppVersionSource` so logic-business
 * keeps zero ohos imports and stays host-runnable under `cjpm test`.
 */
package eudi_logic_business

/** Mirrors iOS `AppBuildType`. */
public enum AppBuildType <: ToString & Equatable<AppBuildType> {
    | RELEASE
    | DEBUG

    public static func fromRawValue(rawValue: String): ?AppBuildType {
        match (rawValue) {
            case "RELEASE" => return RELEASE
            case "DEBUG" => return DEBUG
            case _ => return None
        }
    }

    public prop rawValue: String {
        get() {
            match (this) {
                case RELEASE => "RELEASE"
                case DEBUG => "DEBUG"
            }
        }
    }

    public func toString(): String {
        return this.rawValue
    }

    public operator func ==(other: AppBuildType): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: AppBuildType): Bool {
        return !(this == other)
    }
}

/**
 * Mirrors iOS `AppBuildVariant` (DEMO / DEV). PROD is added per the module
 * contract so the HarmonyOS wallet can express a production variant the iOS
 * scheme encodes outside this enum.
 */
public enum AppBuildVariant <: ToString & Equatable<AppBuildVariant> {
    | DEMO
    | DEV
    | PROD

    public static func fromRawValue(rawValue: String): ?AppBuildVariant {
        match (rawValue) {
            case "DEMO" => return DEMO
            case "DEV" => return DEV
            case "PROD" => return PROD
            case _ => return None
        }
    }

    public prop rawValue: String {
        get() {
            match (this) {
                case DEMO => "DEMO"
                case DEV => "DEV"
                case PROD => "PROD"
            }
        }
    }

    public func toString(): String {
        return this.rawValue
    }

    public operator func ==(other: AppBuildVariant): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: AppBuildVariant): Bool {
        return !(this == other)
    }
}

/**
 * Bundle-version seam. `entry` installs a reader backed by BundleManager;
 * off-device (host unit tests) none is installed and callers get the same
 * placeholder the packaged app carries.
 */
public class AppVersionSource {
    /** Installed by `entry` — reads versionName from the HarmonyOS bundle. */
    private static var reader: ?() -> String = None

    /** Called by the entry composition root before the wallet graph is built. */
    public static func setReader(read: () -> String): Unit {
        AppVersionSource.reader = Some(read)
    }

    /** The bundle versionName, or None off-device / when the read throws. */
    public static func read(): ?String {
        match (AppVersionSource.reader) {
            case Some(read) =>
                try {
                    return Some(read())
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }
}

/**
 * Build-variant seam, mirroring iOS `getBuildVariant()`.
 *
 * On iOS the variant is a property of the packaged app: `ConfigLogic` reads
 * the Info.plist key "Build Variant" and falls back to DEV when it is absent
 * or unrecognised. The HarmonyOS counterpart is the module's `metadata` entry
 * in module.json5, read through BundleManager — but that import belongs to
 * `entry`, so this module keeps the same reader seam as AppVersionSource and
 * stays host-runnable under `cjpm test`.
 */
public class AppBuildVariantSource {
    /** Installed by `entry` — reads the BuildVariant metadata from the bundle. */
    private static var reader: ?() -> String = None

    /** Called by the entry composition root before the wallet graph is built. */
    public static func setReader(read: () -> String): Unit {
        AppBuildVariantSource.reader = Some(read)
    }

    /** The declared variant name, or None off-device / when the read throws. */
    public static func read(): ?String {
        match (AppBuildVariantSource.reader) {
            case Some(read) =>
                try {
                    let name = read()
                    if (name.isEmpty()) {
                        return None
                    }
                    return Some(name)
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }
}

/**
 * Mirrors iOS `getBuildVariant()` exactly: an absent or unrecognised
 * declaration resolves to DEV, so a build that forgets to declare the variant
 * points at the development issuers rather than silently at DEMO.
 */
public func resolveAppBuildVariant(): AppBuildVariant {
    match (AppBuildVariantSource.read()) {
        case Some(name) => return AppBuildVariant.fromRawValue(name) ?? AppBuildVariant.DEV
        case None => return AppBuildVariant.DEV
    }
}

/** Mirrors iOS `KeyChainConfig` (document storage service name + access group). */
public class KeyChainConfig {
    public let documentStorageServiceName: String
    public let keychainAccessGroup: String

    public init(documentStorageServiceName: String, keychainAccessGroup: String) {
        this.documentStorageServiceName = documentStorageServiceName
        this.keychainAccessGroup = keychainAccessGroup
    }
}

/** Mirrors the iOS `ConfigLogic` protocol. */
public interface ConfigLogic {
    /** Build type. */
    prop appBuildType: AppBuildType
    /** Build variant. */
    prop appBuildVariant: AppBuildVariant
    /** App version. */
    prop appVersion: String
    /** Changelog URL (None when not configured). */
    prop changelogUrl: ?String
    /** Wallet requires PID activation. */
    prop forcePidActivation: Bool
    /** Keychain configuration. */
    prop keyChainConfig: KeyChainConfig
}

/**
 * Mirrors iOS `ConfigLogicImpl`: an immutable configuration snapshot.
 * Defaults follow the module contract (DEBUG / DEV) and the HarmonyOS
 * AppScope versionName; `forcePidActivation` is hardcoded false like iOS.
 */
public class ConfigLogicImpl <: ConfigLogic {
    private let buildType: AppBuildType
    private let buildVariant: AppBuildVariant
    private let version: String
    private let changelog: ?String
    private let keyChain: KeyChainConfig

    public init(
        buildType!: AppBuildType = AppBuildType.DEBUG,
        // Default: whatever the packaged app declares (iOS reads the
        // "Build Variant" Info.plist key here); DEV when nothing is declared.
        buildVariant!: AppBuildVariant = resolveAppBuildVariant(),
        // Empty → read the AppScope/app.json5 versionName from the bundle at
        // runtime (iOS reads CFBundleShortVersionString the same way).
        appVersion!: String = "",
        changelogUrl!: ?String = Some("https://github.com/CJPLUK/EUDI_Harmony"),
        keyChainConfig!: ?KeyChainConfig = None
    ) {
        this.buildType = buildType
        this.buildVariant = buildVariant
        this.version = if (appVersion.isEmpty()) {
            ConfigLogicImpl.readBundleVersionName()
        } else {
            appVersion
        }
        this.changelog = changelogUrl
        this.keyChain = keyChainConfig ?? KeyChainConfig(
            "eu.europa.ec.euidi.eudi.document.storage",
            "eu.europa.ec.euidi"
        )
    }

    private static func readBundleVersionName(): String {
        // Bundle info is unavailable off-device (unit tests) — fall back to
        // the same placeholder the packaged app carries.
        let raw = AppVersionSource.read() ?? "{yyyy.mm.v}"
        // versionName carries the release-scheme placeholder in braces (the
        // app.json5 schema's template form, akin to iOS $(MARKETING_VERSION));
        // strip them for display, matching the iOS footer.
        if (raw.startsWith("{") && raw.endsWith("}")) {
            let sb = StringBuilder()
            let runes = raw.toRuneArray()
            var i = 1
            while (i < runes.size - 1) {
                sb.append(runes[i])
                i++
            }
            return sb.toString()
        }
        return raw
    }

    public prop appBuildType: AppBuildType {
        get() { this.buildType }
    }

    public prop appBuildVariant: AppBuildVariant {
        get() { this.buildVariant }
    }

    public prop appVersion: String {
        get() { this.version }
    }

    public prop changelogUrl: ?String {
        get() { this.changelog }
    }

    public prop forcePidActivation: Bool {
        get() { false }
    }

    public prop keyChainConfig: KeyChainConfig {
        get() { this.keyChain }
    }
}

/** Factory replacing the iOS Swinject assembly registration for ConfigLogic. */
public func createConfigLogic(): ConfigLogic {
    return ConfigLogicImpl()
}
