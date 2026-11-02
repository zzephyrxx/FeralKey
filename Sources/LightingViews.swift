// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct AgentPaletteEditor: View {
    @ObservedObject var model: LabModel
    private var theme: GlassTheme { model.theme }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing:18) {
                Toggle("固定额度区",isOn:Binding(get:{ model.agentPinned || model.preferredAgentPinned },set:{ model.setAgentPinned($0) }))
                    .disabled((!model.canSyncQuota || model.agentNeedsApply) && !model.agentPinned && !model.preferredAgentPinned)
                Spacer()
                Button("应用额度灯配置") { model.applyAgentConfiguration() }.buttonStyle(FeralButtonStyle(theme:theme,prominent:true)).disabled(!model.canApplyAgent)
            }
            FeralDisclosure("颜色与显示选项",theme:theme,symbol:"paintpalette") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("低额度使用橙 / 红色警示", isOn: Binding(get: { model.agentPalette.warningColors }, set: { model.agentPalette.warningColors = $0; model.saveAgentPalette() }))
                    Text("配色和开关点击应用后生效；固定区保留最后成功值。")
                        .font(.system(size: 11)).foregroundStyle(theme.secondary)
                }.padding(.top, 8)
            }
        }.font(.system(size: 12)).padding(18).glassPane(theme)
    }
}

struct SystemNotificationPanel: View {
    @ObservedObject var model: LabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("系统横幅联动（实验）", isOn: Binding(get: { model.systemNotificationsEnabled || model.preferredNotifications }, set: { model.setSystemNotifications($0) }))
                    .disabled((!model.connected || !model.appliedLight) && !model.systemNotificationsEnabled && !model.preferredNotifications)
                Spacer()
                Button("授权设置") { model.accessibilityPermissions() }
                Button("测试横幅") { model.testSystemBanner() }.disabled(!model.systemNotificationsEnabled)
            }
            Text(model.systemNotificationStatus).font(.system(size: 11)).foregroundStyle(model.theme.secondary)
            FeralDisclosure("联动说明",theme:model.theme,symbol:"info.circle") {
                Text("需要辅助功能权限；只检测横幅，不读取正文。设置会保存，连接后恢复；勿扰或系统更新可能影响检测。")
                    .font(.system(size: 11)).foregroundStyle(model.theme.secondary).padding(.top, 6)
            }.font(.system(size: 11))
        }.font(.system(size: 12)).padding(.vertical, 12)
    }
}
