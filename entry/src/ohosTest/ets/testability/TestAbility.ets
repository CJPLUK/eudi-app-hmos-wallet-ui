import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class TestAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(0x0000, 'CJTest', '%{public}s', 'TestAbility onCreate');
  }

  onDestroy() {
    hilog.info(0x0000, 'CJTest', '%{public}s', 'TestAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    windowStage.loadContent('testability/pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'CJTest', 'Failed to load TestAbility page: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'CJTest', '%{public}s', 'TestAbility page loaded');
    });
  }

  onWindowStageDestroy() {
    hilog.info(0x0000, 'CJTest', '%{public}s', 'TestAbility onWindowStageDestroy');
  }

  onForeground() {
    hilog.info(0x0000, 'CJTest', '%{public}s', 'TestAbility onForeground');
  }

  onBackground() {
    hilog.info(0x0000, 'CJTest', '%{public}s', 'TestAbility onBackground');
  }
}
