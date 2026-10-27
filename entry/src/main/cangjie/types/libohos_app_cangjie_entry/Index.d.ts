export declare function cborSelfTest(): string
export declare function cryptoSelfTest(): string
export declare function setAbilityContext(context: Object): string
export declare function handleDeepLink(uri: string): string
export declare function registerScanLauncher(launch: () => void): string
export declare function deliverScanResult(text: string): string
export declare function cancelScanResult(): string
export declare function registerFilePickerLauncher(launch: () => void): string
export declare function deliverFilePickerResult(path: string): string
export declare function cancelFilePickerResult(): string
export declare function registerBluetoothStateReader(readState: () => number): string
export declare function deliverBluetoothState(state: number): string
export declare function registerGattOperations(
  open: (serviceUuid: string, identHex: string) => void,
  startAdvertise: (serviceUuid: string) => void,
  stopAdvertise: () => void,
  notify: (deviceId: string, serviceUuid: string, characteristicUuid: string, valueHex: string) => void,
  respond: (deviceId: string, transId: number, status: number, offset: number, valueHex: string) => void,
  close: (serviceUuid: string) => void): string
export declare function drainGattCommands(): string
export declare function deliverGattNotifyResult(id: number, succeeded: boolean, message: string): string
export declare function deliverGattConnection(deviceId: string, connected: boolean): string
export declare function deliverGattMtu(mtu: number): string
export declare function deliverGattWrite(deviceId: string, transId: number, offset: number, needRsp: boolean,
  characteristicUuid: string, descriptorUuid: string, valueHex: string): string
export declare function deliverGattRead(deviceId: string, transId: number, offset: number,
  characteristicUuid: string, descriptorUuid: string): string
export declare function deliverBiometryCapability(authType: number, status: number): string
export declare function drainBiometryCommands(): string
export declare function deliverBiometryResult(id: number, resultCode: number): string
