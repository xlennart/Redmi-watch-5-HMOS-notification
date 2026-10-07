// Illustrative V1 ArkUI page; not a built application.
// Export colors with scripts/export_tokens.py, then merge the generated
// resources into the target module before using this snippet.
// Match target SDK/API and existing project conventions; OS resources
// select light/dark colors. State below is local to this page, not persisted.
@Entry
@Component
struct HarmonyDesignStarter {
  @State reminders: boolean = false

  build() {
    Column({ space: 20 }) {
      Row() {
        Column({ space: 4 }) {
          Text('早上好')
            .fontSize(14)
            .fontColor($r('app.color.harmony_muted'))
          Text('偏好设置')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.harmony_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('重置')
          .backgroundColor($r('app.color.harmony_action_surface'))
          .fontColor($r('app.color.harmony_action'))
          .onClick(() => {
            this.reminders = false
          })
      }
      .width('100%')

      Column({ space: 12 }) {
        Text('每日提醒')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.harmony_text'))
        Text(this.reminders ? '本页提醒偏好已开启' : '本页提醒偏好已关闭')
          .fontSize(14)
          .fontColor($r('app.color.harmony_muted'))
        Toggle({ type: ToggleType.Switch, isOn: this.reminders })
          .accessibilityText('每日提醒')
          .onChange((value: boolean) => {
            this.reminders = value
          })
      }
      .width('100%')
      .padding(20)
      .borderRadius(20)
      .backgroundColor($r('app.color.harmony_surface'))

      Text('这是本页状态示例；持久化与通知能力按项目实际实现。')
        .fontSize(12)
        .fontColor($r('app.color.harmony_muted'))
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor($r('app.color.harmony_page'))
  }
}
