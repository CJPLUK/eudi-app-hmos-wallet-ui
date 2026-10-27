@Entry
@Component
struct Index {
  @State message: string = 'EUDI Cangjie unit tests';

  build() {
    Row() {
      Column() {
        Text(this.message)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
    .height('100%')
  }
}
