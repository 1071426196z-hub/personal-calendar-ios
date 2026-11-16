# 私人日历（iOS）

SwiftUI 原生 iPhone 日历，最低 iOS 27。农历和黄历计算资源随应用打包。事项保存于设备内。

「导入与同步」使用 EventKit 读取系统日历和提醒事项，支持选择来源。组件由 WidgetKit 提供，小号展示日期和农历，中号与大号展示月历，倒数日组件在桌面单独配置。组件不要求 App Groups。

在 Actions 中运行 Build iOS IPA，完成后下载 PersonalCalendar.ipa。这个 IPA 由 Sideloadly 用个人 Apple 账户签名。使用 Xcode 27 的 Mac 也可运行 `bash ios/build-ipa.sh` 本地构建。
