// ArkTS 容器页:经官方 CJHybridComponent 嵌入仓颉 AppRoot 组合根。
// aboutToAppear 保留 cbor / crypto 自检(JSModule 函数级链路)作回归信号,结果打 hilog。
import { CJHybridComponent } from '@cangjie/cjhybridcomponent';
import { cborSelfTest, cryptoSelfTest, setAbilityContext, handleDeepLink,
         registerScanLauncher, deliverScanResult, cancelScanResult,
         registerFilePickerLauncher, deliverFilePickerResult, cancelFilePickerResult,
         registerBluetoothStateReader, deliverBluetoothState, registerGattOperations,
         drainGattCommands, deliverGattNotifyResult, deliverGattConnection, deliverGattMtu, deliverGattWrite,
         deliverGattRead, deliverBiometryCapability, drainBiometryCommands,
         deliverBiometryResult } from 'libohos_app_cangjie_entry.so';
import { DeepLinkState } from '../common/DeepLinkState';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError, settings } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import hilog from '@ohos.hilog';
import { access, ble } from '@kit.ConnectivityKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

@Entry
@Component
struct Index {
  private gattServer: ble.GattServer | undefined = undefined;
  private advertisingId: number | undefined = undefined;
  private gattCommandPumpId: number | undefined = undefined;
  private biometryAuthType: userAuth.UserAuthType | undefined = undefined;

  aboutToAppear() {
    // Hand the UIAbilityContext to the Cangjie wallet engine BEFORE the AppRoot
    // (and thus the wallet graph) is built, so issued credentials persist in the
    // encrypted RDB store instead of an in-memory fallback.
    const ctxResult: string = setAbilityContext(getContext(this));
    console.info('SET_ABILITY_CONTEXT result=' + ctxResult);
    // Cangjie has no UserAuthenticationKit binding. Probe the real device here
    // before AppRoot is created and publish the modality/enrolment state to the
    // synchronous BiometryController consumed by the wallet screens.
    this.publishBiometryCapability();
    const c: string = cborSelfTest();
    console.info('CBOR_TEST result=' + c);
    const k: string = cryptoSelfTest();
    console.info('CRYPTO_TEST result=' + k);
    // Forward a cold-start deep-link URI (captured in EntryAbility.onCreate)
    // to the Cangjie DeepLinkRouter now that the module is loaded. The
    // authenticated Dashboard consumes it on first appear.
    const dl: string | undefined = DeepLinkState.pending;
    if (dl) {
      DeepLinkState.pending = undefined;
      const r: string = handleDeepLink(dl);
      console.info('DEEP_LINK forwarded result=' + r);
    }
    // Camera QR scanning lives on the ArkTS side: HMS Scan Kit has no Cangjie
    // binding. Hand the Cangjie ScanBridge a launcher it can call when a wallet
    // screen needs a scan. startScanForResult must run in an ArkUI page context,
    // which is why the closure is registered from here rather than the ability.
    registerScanLauncher((): void => this.launchScan());
    // RQES document picking lives on the ArkTS side: DocumentViewPicker has no
    // Cangjie binding. The Sign-document screen asks FilePickerBridge for a PDF;
    // this launcher opens the picker, copies the file into the app cache (so the
    // native signer gets a readable path) and reports it back.
    registerFilePickerLauncher((): void => { this.launchFilePicker(); });

    // Mirror iOS BluetoothKit availability with the platform adapter state.
    // GATT server creation is deliberately not used as a radio-state probe.
    registerBluetoothStateReader((): number => access.getState() as number);
    try {
      const initialState: number = access.getState() as number;
      deliverBluetoothState(initialState);
      access.on('stateChange', (state: access.BluetoothState): void => {
        deliverBluetoothState(state as number);
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, 'BLE', 'initial adapter state unavailable code=%{public}d', err.code);
    }
    registerGattOperations(
      (serviceUuid: string, identHex: string): void => this.openGattServer(serviceUuid, identHex),
      (serviceUuid: string): void => this.startGattAdvertising(serviceUuid),
      (): void => this.stopGattAdvertising(),
      (deviceId: string, serviceUuid: string, characteristicUuid: string, valueHex: string): void =>
        this.notifyGatt(deviceId, serviceUuid, characteristicUuid, valueHex),
      (deviceId: string, transId: number, status: number, offset: number, valueHex: string): void =>
        this.respondGatt(deviceId, transId, status, offset, valueHex),
      (serviceUuid: string): void => this.closeGattServer(serviceUuid));
    // Cangjie may produce notify/stop/close operations from worker threads.
    // Drain them on ArkTS's UI event loop so no retained JS function is ever
    // invoked from a foreign Cangjie thread.
    this.gattCommandPumpId = setInterval((): void => {
      this.drainGattCommandQueue();
      this.drainBiometryCommandQueue();
    }, 10);
  }

  aboutToDisappear() {
    if (this.gattCommandPumpId !== undefined) {
      clearInterval(this.gattCommandPumpId);
      this.gattCommandPumpId = undefined;
    }
  }

  private drainGattCommandQueue(): void {
    const batch: string = drainGattCommands();
    if (batch.length === 0) {
      return;
    }
    for (const command of batch.split('\n')) {
      const parts: string[] = command.split('|');
      try {
        switch (parts[0]) {
          case 'OPEN':
            this.openGattServer(parts[1], parts[2] ?? '');
            break;
          case 'START':
            this.startGattAdvertising(parts[1]);
            break;
          case 'STOP':
            this.stopGattAdvertising();
            break;
          case 'NOTIFY':
            this.executeNotifyCommand(Number(parts[1]), parts[2], parts[3], parts[4], parts[5] ?? '');
            break;
          case 'RESPOND':
            this.respondGatt(parts[1], Number(parts[2]), Number(parts[3]),
              Number(parts[4]), parts[5] ?? '');
            break;
          case 'CLOSE':
            this.closeGattServer(parts[1]);
            break;
          default:
            hilog.error(0x0000, 'MdocGattArkTS', 'unknown command %{public}s', parts[0]);
        }
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(0x0000, 'MdocGattArkTS',
          'command %{public}s failed code=%{public}d msg=%{public}s', parts[0], err.code, err.message);
      }
    }
  }

  private probeBiometry(authType: userAuth.UserAuthType): number {
    try {
      userAuth.getAvailableStatus(authType, userAuth.AuthTrustLevel.ATL1);
      return userAuth.UserAuthResultCode.SUCCESS;
    } catch (e) {
      return (e as BusinessError).code;
    }
  }

  private publishBiometryCapability(): void {
    const fingerprintStatus: number = this.probeBiometry(userAuth.UserAuthType.FINGERPRINT);
    const faceStatus: number = this.probeBiometry(userAuth.UserAuthType.FACE);

    let selectedType: userAuth.UserAuthType | undefined = undefined;
    let selectedStatus: number = userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT;
    // Prefer an enrolled modality. If neither is enrolled, retain the modality
    // that exists so Settings can show the same enrolment guidance as iOS.
    if (fingerprintStatus === userAuth.UserAuthResultCode.SUCCESS) {
      selectedType = userAuth.UserAuthType.FINGERPRINT;
      selectedStatus = fingerprintStatus;
    } else if (faceStatus === userAuth.UserAuthResultCode.SUCCESS) {
      selectedType = userAuth.UserAuthType.FACE;
      selectedStatus = faceStatus;
    } else if (fingerprintStatus === userAuth.UserAuthResultCode.NOT_ENROLLED) {
      selectedType = userAuth.UserAuthType.FINGERPRINT;
      selectedStatus = fingerprintStatus;
    } else if (faceStatus === userAuth.UserAuthResultCode.NOT_ENROLLED) {
      selectedType = userAuth.UserAuthType.FACE;
      selectedStatus = faceStatus;
    } else if (fingerprintStatus === 201 || faceStatus === 201) {
      // Preserve permission denial instead of misreporting it as absent hardware.
      selectedStatus = 201;
    }

    this.biometryAuthType = selectedType;
    deliverBiometryCapability(selectedType === undefined ? 0 : selectedType as number, selectedStatus);
    hilog.info(0x0000, 'Biometry',
      'capability fingerprint=%{public}d face=%{public}d selected=%{public}d status=%{public}d',
      fingerprintStatus, faceStatus, selectedType === undefined ? 0 : selectedType as number, selectedStatus);
  }

  private drainBiometryCommandQueue(): void {
    const batch: string = drainBiometryCommands();
    if (batch.length === 0) {
      return;
    }
    for (const command of batch.split('\n')) {
      const parts: string[] = command.split('|');
      if (parts[0] === 'AUTH') {
        this.startBiometry(Number(parts[1]));
      } else if (parts[0] === 'SETTINGS') {
        this.openBiometrySettings();
      }
    }
  }

  /**
   * userAuth rejects an empty challenge with 401 ("The length of challenge
   * cannot exceed 32"), so send 32 random bytes — the freshness nonce the
   * platform echoes back inside the auth token.
   */
  private authChallenge(): Uint8Array {
    try {
      const random = cryptoFramework.createRandom();
      return new Uint8Array(random.generateRandomSync(32).data);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, 'Biometry', 'random challenge unavailable code=%{public}d; using a counter',
        err.code);
      const fallback = new Uint8Array(32);
      const seed: number = Date.now();
      for (let i = 0; i < fallback.length; i++) {
        fallback[i] = (seed >> (i % 4 * 8) ^ i * 31) & 0xFF;
      }
      return fallback;
    }
  }

  private startBiometry(requestId: number): void {
    if (this.biometryAuthType === undefined) {
      deliverBiometryResult(requestId, userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT);
      return;
    }
    const authParam: userAuth.AuthParam = {
      challenge: this.authChallenge(),
      authType: [this.biometryAuthType],
      authTrustLevel: userAuth.AuthTrustLevel.ATL1
    };
    const widgetParam: userAuth.WidgetParam = {
      title: 'Authenticate to use EUDI Wallet',
      navigationButtonText: 'Use PIN'
    };
    try {
      const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          try { instance.off('result', callback); } catch (_) {}
          hilog.info(0x0000, 'Biometry', 'authentication result=%{public}d', result.result);
          deliverBiometryResult(requestId, result.result);
        }
      };
      instance.on('result', callback);
      instance.start();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, 'Biometry', 'authentication failed code=%{public}d msg=%{public}s',
        err.code, err.message);
      deliverBiometryResult(requestId, err.code || userAuth.UserAuthResultCode.GENERAL_ERROR);
    }
  }

  private openBiometrySettings(): void {
    try {
      settings.openBiometricsSettingsPage(getContext(this));
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, 'Biometry', 'open settings failed code=%{public}d msg=%{public}s',
        err.code, err.message);
    }
  }

  private executeNotifyCommand(id: number, deviceId: string, serviceUuid: string,
    characteristicUuid: string, valueHex: string): void {
    try {
      this.notifyGatt(deviceId, serviceUuid, characteristicUuid, valueHex);
      deliverGattNotifyResult(id, true, '');
    } catch (e) {
      const err = e as BusinessError;
      const message: string = 'code=' + err.code + ' msg=' + err.message;
      hilog.warn(0x0000, 'MdocGattArkTS', 'notify rejected %{public}s', message);
      deliverGattNotifyResult(id, false, message);
    }
  }

  private hexBuffer(hex: string): ArrayBuffer {
    const bytes = new Uint8Array(Math.floor(hex.length / 2));
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = Number.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return bytes.buffer;
  }

  private bufferHex(value: ArrayBuffer): string {
    const bytes = new Uint8Array(value);
    let result = '';
    for (let i = 0; i < bytes.length; i++) {
      result += bytes[i].toString(16).padStart(2, '0');
    }
    return result;
  }

  private descriptor(serviceUuid: string, characteristicUuid: string): ble.BLEDescriptor {
    return {
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: '00002902-0000-1000-8000-00805F9B34FB',
      descriptorValue: new ArrayBuffer(2)
    };
  }

  private characteristic(serviceUuid: string, uuid: string, value: ArrayBuffer,
    properties: ble.GattProperties, descriptors: Array<ble.BLEDescriptor>): ble.BLECharacteristic {
    return {
      serviceUuid: serviceUuid,
      characteristicUuid: uuid,
      characteristicValue: value,
      descriptors: descriptors,
      properties: properties
    };
  }

  private openGattServer(serviceUuid: string, identHex: string): void {
    const stateUuid = '00000001-A123-48CE-896B-4C76973373E6';
    const c2sUuid = '00000002-A123-48CE-896B-4C76973373E6';
    const s2cUuid = '00000003-A123-48CE-896B-4C76973373E6';
    const identUuid = '00000004-A123-48CE-896B-4C76973373E6';
    const chars: Array<ble.BLECharacteristic> = [
      this.characteristic(serviceUuid, stateUuid, new ArrayBuffer(0),
        { write: true, writeNoResponse: true, notify: true }, [this.descriptor(serviceUuid, stateUuid)]),
      this.characteristic(serviceUuid, c2sUuid, new ArrayBuffer(0),
        { write: true, writeNoResponse: true }, []),
      this.characteristic(serviceUuid, s2cUuid, new ArrayBuffer(0),
        { notify: true }, [this.descriptor(serviceUuid, s2cUuid)])
    ];
    if (identHex.length > 0) {
      chars.push(this.characteristic(serviceUuid, identUuid, this.hexBuffer(identHex), { read: true }, []));
    }
    const service: ble.GattService = { serviceUuid: serviceUuid, isPrimary: true, characteristics: chars };

    this.gattServer = ble.createGattServer();
    this.gattServer.on('connectionStateChange', (state: ble.BLEConnectionChangeState): void => {
      deliverGattConnection(state.deviceId, state.state === 2);
    });
    this.gattServer.on('BLEMtuChange', (mtu: number): void => {
      deliverGattMtu(mtu);
    });
    this.gattServer.on('characteristicWrite', (req: ble.CharacteristicWriteRequest): void => {
      deliverGattWrite(req.deviceId, req.transId, req.offset, req.needRsp,
        req.characteristicUuid, '', this.bufferHex(req.value));
    });
    this.gattServer.on('characteristicRead', (req: ble.CharacteristicReadRequest): void => {
      deliverGattRead(req.deviceId, req.transId, req.offset, req.characteristicUuid, '');
    });
    this.gattServer.on('descriptorWrite', (req: ble.DescriptorWriteRequest): void => {
      deliverGattWrite(req.deviceId, req.transId, req.offset, req.needRsp,
        req.characteristicUuid, req.descriptorUuid, this.bufferHex(req.value));
    });
    this.gattServer.on('descriptorRead', (req: ble.DescriptorReadRequest): void => {
      deliverGattRead(req.deviceId, req.transId, req.offset, req.characteristicUuid, req.descriptorUuid);
    });
    this.gattServer.addService(service);
    hilog.info(0x0000, 'MdocGattArkTS', 'service registered %{public}s', serviceUuid);
  }

  private startGattAdvertising(serviceUuid: string): void {
    const params: ble.AdvertisingParams = {
      advertisingSettings: { interval: 160, txPower: 0, connectable: true },
      advertisingData: { serviceUuids: [serviceUuid], manufactureData: [], serviceData: [] },
      duration: 0
    };
    ble.startAdvertising(params).then((id: number): void => {
      this.advertisingId = id;
      hilog.info(0x0000, 'MdocGattArkTS', 'advertising started id=%{public}d', id);
    }).catch((e: BusinessError): void => {
      hilog.error(0x0000, 'MdocGattArkTS', 'advertising failed code=%{public}d msg=%{public}s', e.code, e.message);
    });
  }

  private stopGattAdvertising(): void {
    if (this.advertisingId !== undefined) {
      try { ble.stopAdvertising(this.advertisingId); } catch (_) {}
      this.advertisingId = undefined;
    }
  }

  private notifyGatt(deviceId: string, serviceUuid: string, characteristicUuid: string, valueHex: string): void {
    this.gattServer?.notifyCharacteristicChanged(deviceId, {
      serviceUuid: serviceUuid, characteristicUuid: characteristicUuid,
      characteristicValue: this.hexBuffer(valueHex), confirm: false
    });
  }

  private respondGatt(deviceId: string, transId: number, status: number, offset: number, valueHex: string): void {
    this.gattServer?.sendResponse({
      deviceId: deviceId, transId: transId, status: status, offset: offset, value: this.hexBuffer(valueHex)
    });
  }

  private closeGattServer(serviceUuid: string): void {
    this.stopGattAdvertising();
    if (this.gattServer !== undefined) {
      try { this.gattServer.removeService(serviceUuid); } catch (_) {}
      try { this.gattServer.close(); } catch (_) {}
      this.gattServer = undefined;
    }
  }


  // Opens the document picker, copies the chosen PDF into the app cache, and
  // reports the readable path back to the Cangjie FilePickerBridge.
  async launchFilePicker(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pdf'];
      const uris: Array<string> = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        cancelFilePickerResult();
        return;
      }
      const uri: string = uris[0];
      // Preserve the original file name (iOS shows e.g. "sample1.pdf", not a temp name).
      // Copy into a per-pick timestamped subdir so same-named files never collide.
      const origName: string = uri.substring(uri.lastIndexOf('/') + 1) || ('document_' + Date.now().toString() + '.pdf');
      const cacheDir: string = getContext(this).cacheDir;
      const subDir: string = cacheDir + '/rqes_' + Date.now().toString();
      fs.mkdirSync(subDir);
      const dest: string = subDir + '/' + origName;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
      hilog.info(0x0000, 'RQES', 'picked+copied to cache len=%{public}d', dest.length);
      deliverFilePickerResult(dest);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, 'RQES', 'file pick threw code=%{public}d', err.code);
      cancelFilePickerResult();
    }
  }

  // Opens the system scan page and reports the outcome back to Cangjie. The
  // decoded text goes through the same validation the manual-entry path uses.
  launchScan(): void {
    try {
      scanBarcode.startScanForResult(getContext(this),
        {
          scanTypes: [scanCore.ScanType.QR_CODE, scanCore.ScanType.DATAMATRIX_CODE],
          enableMultiMode: true,
          enableAlbum: true
        } as scanBarcode.ScanOptions,
        (error: BusinessError, result: scanBarcode.ScanResult): void => {
          if (error) {
            // Includes the user simply backing out of the scanner.
            hilog.info(0x0000, 'SCAN', 'startScanForResult error code=%{public}d', error.code);
            cancelScanResult();
            return;
          }
          const value: string = result.originalValue ?? '';
          hilog.info(0x0000, 'SCAN', 'scanned len=%{public}d', value.length);
          if (value.length > 0) {
            deliverScanResult(value);
          } else {
            cancelScanResult();
          }
        });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, 'SCAN', 'startScanForResult threw code=%{public}d', err.code);
      cancelScanResult();
    }
  }

  build() {
    Row() {
      CJHybridComponent({
        library: "ohos_app_cangjie_entry",   // 仓颉页面所在 package 名
        component: "AppRoot"                 // EUDI 组合根:Navigation 壳 + StartupView
      })
        .height('100%')
        .width('100%')
        // The hybrid surface must expand itself: expanding only the parent Row
        // still leaves the Cangjie root laid out inside the safe area.
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .height('100%')
    .width('100%')
    // Extend the Cangjie root under the bottom system bar so full-screen
    // overlays (sheet/alert scrims) can cover the home-indicator area.
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
