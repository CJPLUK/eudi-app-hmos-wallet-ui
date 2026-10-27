/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * Device half of the iOS logic-business ReachabilityController port. The
 * platform-free halves (BleAvailibity / BleRadioState enums, state mappings,
 * BluetoothStateBridge, the ReachabilityController interface) live in
 * eudi_logic_business/reachability_controller.cj; that module is host-runnable
 * (run_tests.sh HOST_MODULES) and must not import device-only OHOS packages.
 * This file carries the parts that need them — the AtManager ACCESS_BLUETOOTH
 * permission prompt and the Bluetooth-settings Want — the same split biometry
 * uses (interface in the logic layer, device impl outside the host set).
 */
package ohos_app_cangjie_entry

import ohos.ability_access_ctrl.{AbilityAccessCtrl, GrantStatus}
import ohos.bundle.bundle_manager.{BundleManager, BundleFlag}
import ohos.business_exception.BusinessException
import ohos.security.permission_request_result.PermissionRequestResult
import ohos.app.ability.ui_ability.UIAbilityContext
import ohos.app.ability.want.Want
import eudi_logic_business.{
    ReachabilityController, BleAvailibity, BLE_PERMISSION,
    mapBleAvailability, probeBleRadio, allPermissionsGranted
}

// System Settings deep link for the Bluetooth page (HarmonyOS settings Want).
const BLE_SETTINGS_BUNDLE: String = "com.huawei.hmos.settings"
const BLE_SETTINGS_ABILITY: String = "com.huawei.hmos.settings.MainAbility"
const BLE_SETTINGS_URI: String = "bluetooth_entry"

/**
 * Device implementation:
 * - hasInternet: report true so network flows stay usable.
 * - BLE: check the ACCESS_BLUETOOTH grant (request it when missing, given an
 *   ability context), then read the radio state and apply the iOS
 *   BluetoothKit mapping (available / disabled / noPermission / unavailable).
 * - openBleSettings: `startAbility` into the system Bluetooth settings page.
 */
public class ReachabilityControllerImpl <: ReachabilityController {
    /** Supplies the UIAbilityContext (permission dialog + settings deep link); None in preview/tests. */
    private let contextProvider: () -> ?UIAbilityContext

    public init() {
        this.contextProvider = { => Option<UIAbilityContext>.None }
    }

    public init(contextProvider: () -> ?UIAbilityContext) {
        this.contextProvider = contextProvider
    }

    public func hasInternet(): Bool {
        return true
    }

    public func getBleAvailibity(callback: (BleAvailibity) -> Unit): Unit {
        if (isBlePermissionGranted()) {
            callback(mapBleAvailability(probeBleRadio()))
            return
        }
        match (this.contextProvider()) {
            case Some(ctx) => this.requestBlePermission(ctx, callback)
            case None =>
                println("[entry] ReachabilityController: no ability context, cannot request ${BLE_PERMISSION}")
                callback(BleAvailibity.noPermission)
        }
    }

    /** Mirrors the camera-permission prompt of the QR scanner for ACCESS_BLUETOOTH. */
    private func requestBlePermission(ctx: UIAbilityContext, callback: (BleAvailibity) -> Unit): Unit {
        try {
            AbilityAccessCtrl.createAtManager().requestPermissionsFromUser(
                ctx,
                [BLE_PERMISSION],
                { err: ?BusinessException, result: ?PermissionRequestResult =>
                    let granted = match ((err, result)) {
                        case (None, Some(r)) => allPermissionsGranted(r.authResults)
                        case _ => false
                    }
                    if (granted) {
                        callback(mapBleAvailability(probeBleRadio()))
                    } else {
                        callback(BleAvailibity.noPermission)
                    }
                }
            )
        } catch (e: Exception) {
            println("[entry] ReachabilityController: requestPermissionsFromUser failed: ${e.message}")
            callback(BleAvailibity.noPermission)
        }
    }

    public func openBleSettings(): Unit {
        match (this.contextProvider()) {
            case Some(ctx) =>
                try {
                    ctx.startAbility(Want(
                        bundleName: BLE_SETTINGS_BUNDLE,
                        abilityName: BLE_SETTINGS_ABILITY,
                        uri: BLE_SETTINGS_URI
                    ))
                } catch (e: Exception) {
                    println("[entry] ReachabilityController.openBleSettings failed: ${e.message}")
                }
            case None =>
                println("[entry] ReachabilityController.openBleSettings: no ability context")
        }
    }
}

/** ACCESS_BLUETOOTH grant state of this app's own access token (AtManager.checkAccessToken). */
func isBlePermissionGranted(): Bool {
    try {
        let tokenId = BundleManager
            .getBundleInfoForSelf(BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
            .appInfo
            .accessTokenId
        let status = AbilityAccessCtrl.createAtManager().checkAccessToken(tokenId, BLE_PERMISSION)
        return match (status) {
            case GrantStatus.PermissionGranted => true
            case _ => false
        }
    } catch (e: Exception) {
        println("[entry] ReachabilityController: checkAccessToken failed: ${e.message}")
        return false
    }
}

/** Factory replacing the iOS Swinject assembly registration for ReachabilityController (no ability context). */
public func createReachabilityController(): ReachabilityController {
    return ReachabilityControllerImpl()
}

/** Factory with the ability-context provider the permission prompt / settings deep link need. */
public func createReachabilityController(contextProvider: () -> ?UIAbilityContext): ReachabilityController {
    return ReachabilityControllerImpl(contextProvider)
}
