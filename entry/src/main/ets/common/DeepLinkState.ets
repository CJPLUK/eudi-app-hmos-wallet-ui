// Shared holder for a cold-start deep-link (eudi-openid4vp://...) URI captured by
// EntryAbility.onCreate before the Cangjie .so is loaded. Index.ets aboutToAppear
// reads and forwards it to the Cangjie DeepLinkRouter once the module is ready.
export class DeepLinkState {
  static pending: string | undefined = undefined;
}
