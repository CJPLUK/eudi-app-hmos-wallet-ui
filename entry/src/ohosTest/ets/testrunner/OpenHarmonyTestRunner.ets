// ohosTest runner: loads libeudi_unit_tests.so (test HAP only)
// and prints the DeviceTestRun summary. The app HAP does not contain this .so.
// aa test: -b <bundle> -m entry_test -s unittest OpenHarmonyTestRunner
import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runUnitTests } from 'libeudi_unit_tests.so';

const DOMAIN: number = 0x0000;
const TAG: string = 'CJTest';

export default class OpenHarmonyTestRunner implements TestRunner {
  constructor() {
  }

  onPrepare() {
    hilog.info(DOMAIN, TAG, '%{public}s', 'OpenHarmonyTestRunner onPrepare');
  }

  async onRun() {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onRun: invoking cangjie runUnitTests');
    const abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    let summary: string = '';
    try {
      summary = runUnitTests();
    } catch (e) {
      summary = 'CJ_RUN_THREW: ' + JSON.stringify(e);
    }
    hilog.info(DOMAIN, TAG, 'CJ_TEST_SUMMARY: %{public}s', summary);
    abilityDelegator.print('CJ_TEST_SUMMARY: ' + summary);
    // Bound the metric so `failed=10` cannot match `failed=0`.
    const failedZero: boolean = /(?:^|\s)failed=0(?!\d)/.test(summary);
    const errorZero: boolean = /(?:^|\s)error=0(?!\d)/.test(summary);
    const ok: boolean = failedZero && errorZero;
    abilityDelegator.finishTest('cangjie unit tests: ' + summary, ok ? 0 : -1, (err) => {
      hilog.info(DOMAIN, TAG, 'finishTest err: %{public}s', JSON.stringify(err) ?? '');
    });
  }
}
