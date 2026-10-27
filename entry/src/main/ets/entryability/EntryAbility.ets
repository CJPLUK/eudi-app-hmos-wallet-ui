import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { handleDeepLink } from 'libohos_app_cangjie_entry.so';
import { DeepLinkState } from '../common/DeepLinkState';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    // Deep-link (eudi-openid4vp://...) cold start: the Cangjie .so may not be
    // loaded yet at onCreate, so stash the launch URI on globalThis and let
    // Index.ets aboutToAppear forward it to the Cangjie DeepLinkRouter once the
    // module is ready.
    if (want.uri) {
      DeepLinkState.pending = want.uri;
      hilog.info(0x0000, 'testTag', 'deep-link (onCreate) captured');
    }
    // ArkWeb DevTools (CDP) must stay off in shipped HAPs. Issuance-page
    // scripting is gated separately by DEBUG_ISSUER_AUTOFILL in Cangjie (false).
    const DEBUG_WEB_INSPECT: boolean = false;
    if (DEBUG_WEB_INSPECT) {
      try {
        webview.WebviewController.setWebDebuggingAccess(true);
      } catch (e) {
        hilog.error(0x0000, 'testTag', 'setWebDebuggingAccess failed: %{public}s', JSON.stringify(e) ?? '');
      }
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onNewWant');
    // Warm-start deep link: the Cangjie module is already loaded, forward the
    // URI straight to DeepLinkRouter (the Dashboard consumes it on next appear).
    if (want.uri) {
      try {
        handleDeepLink(want.uri);
      } catch (e) {
        hilog.error(0x0000, 'testTag', 'handleDeepLink(onNewWant) failed: %{public}s', JSON.stringify(e) ?? '');
      }
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
      // Transparent system navigation bar: the app content (expandSafeArea)
      // paints under the home-indicator area, so full-screen dialog scrims can
      // cover the whole screen instead of stopping at an opaque white bar.
      try {
        const mainWindow = windowStage.getMainWindowSync();
        mainWindow.setWindowSystemBarProperties({
          navigationBarColor: '#00000000'
        });
      } catch (e) {
        hilog.error(0x0000, 'testTag', 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(e) ?? '');
      }
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  // Consume the hardware/gesture Back at the entry (PIN/biometry) screen so it
  // does not exit the app — the auth gate must not be "backed out of". This is
  // only reached when the in-app Navigation did not already handle Back (i.e. the
  // first/entry destination); on every pushed page the NavDestination pops first,
  // so normal in-page Back still works there.
  onBackPressed(): boolean {
    return true;
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
