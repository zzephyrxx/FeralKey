// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct NotificationEditor: View {
    @ObservedObject var model: LabModel
    private var theme: GlassTheme { model.theme }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Picker("预设", selection: Binding(get: { model.notificationSettings.pattern }, set: { model.notificationSettings.pattern = $0; model.saveNotification() })) {
                    ForEach(NotificationPattern.allCases) { Text($0.title).tag($0) }
                }.frame(width: 220)
                ColorPicker("颜色", selection: Binding(get: {
                    let c = model.notificationSettings.color
                    return Color(red: Double(c.r)/255, green: Double(c.g)/255, blue: Double(c.b)/255)
                }, set: { value in
                    let c = NSColor(value).usingColorSpace(.deviceRGB) ?? .orange
                    model.notificationSettings.color = RGB(r: UInt8(min(255,max(0,c.redComponent*255))), g: UInt8(min(255,max(0,c.greenComponent*255))), b: UInt8(min(255,max(0,c.blueComponent*255))))
                    model.saveNotification()
                }), supportsOpacity: false)
                Spacer()
                Button("测试 5 秒…") { model.testNotification() }.disabled(!model.connected || !model.appliedLight)
            }
            HStack {
                Toggle("编辑通知键区", isOn: $model.notificationEditing).toggleStyle(.switch)
                Text("\(model.effectiveNotificationKeys.count) 个键").foregroundStyle(theme.secondary)
                Toggle("预览",isOn:$model.notificationPreview)
                Spacer()
                Button("保存通知设置") { model.applyRegionSettings() }
            }
            if model.notificationEditing {
                HStack {
                    Text("点击上方按键选择").foregroundStyle(theme.secondary)
                    Spacer(); Button("数字区") { model.resetNotificationKeys() }
                    Button("清空") { model.notificationSettings.keys = []; model.saveNotification() }
                }
            }
            if model.notificationSettings.pattern.motion != nil {
                Toggle("实体动态通知（实验）", isOn: Binding(get: { model.dynamicNotificationsEnabled || model.preferredDynamicNotifications }, set: { model.setDynamicNotifications($0) }))
                Text("通知持续 5 秒；使用实时通道，不反复保存配置。") .font(.system(size: 11)).foregroundStyle(theme.secondary)
            }
            Text("平时随整体灯光 · 通知显示 5 秒 · 静态图案自动呼吸").font(.system(size:11)).foregroundStyle(theme.secondary)
            if model.notificationOverlapCount > 0 { Text("\(model.notificationOverlapCount) 个重叠键优先显示额度。").font(.system(size: 11)).foregroundStyle(theme.warning) }
        }.font(.system(size: 12)).padding(18).glassPane(theme)
    }
}

struct ShortcutEditor: View {
    @ObservedObject var model: LabModel
    private var theme: GlassTheme { model.theme }
    private var keys: [PhysicalKey] {
        var seen = Set<String>()
        return model.layout.keys.filter { $0.keyCode != "Key_Fn" && (model.codes[$0.keyCode] ?? UInt32.max) <= 0xffff && seen.insert($0.keyCode).inserted }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("一个实体键，执行一组快捷键").font(.system(size: 17, weight: .semibold))
            Text("选择实体键，再搭配组合键。")
                .font(.system(size: 12)).foregroundStyle(theme.secondary)
            Picker("常用操作", selection: Binding(get: { model.chosenPreset }, set: { model.setShortcutPreset($0) })) {
                Text("自定义组合键").tag("custom")
                ForEach(ShortcutPreset.all) { Text($0.title).tag($0.id) }
            }.frame(maxWidth: 440)

            HStack(spacing: 12) {
                ForEach(Array([(UInt8(1),"⌃ Control"),(2,"⇧ Shift"),(4,"⌥ Option"),(8,"⌘ Command")].enumerated()), id: \.offset) { _, item in
                    let selected = model.shortcutModifiers & item.0 != 0
                    Button {
                        model.chosenPreset = "custom"
                        if selected { model.shortcutModifiers &= ~item.0 } else { model.shortcutModifiers |= item.0 }
                    } label: {
                        Text(item.1).font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundStyle(selected ? theme.foreground : theme.secondary)
                            .background(selected ? theme.accent.opacity(0.2) : theme.keyFill, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? theme.accent.opacity(0.6) : theme.edge, lineWidth: 0.8))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            HStack {
                Picker("主键", selection: Binding(get: { model.shortcutKey }, set: { model.shortcutKey = $0; model.chosenPreset = "custom" })) { ForEach(keys, id: \.keyCode) { Text($0.label).tag($0.keyCode) } }.frame(width: 190)
                Spacer()
                Text("实体键：" + (model.layout.keys.first { $0.id == model.selectedKey }?.label ?? "未选择")).font(.system(size: 12))
                Button("加入组合键映射") { model.stageCustomShortcut() }
                    .buttonStyle(FeralButtonStyle(theme: theme, prominent: true)).disabled(model.selectedKey == nil)
            }
            FeralDisclosure("预设说明",theme:theme,symbol:"command") {
                Text(ShortcutPreset.all.first { $0.id == model.chosenPreset }?.detail ?? "同时按下的组合键；应用自定义快捷键可能影响结果。")
                    .font(.system(size: 11)).foregroundStyle(theme.secondary)
            }.font(.system(size: 11))
        }.padding(18).glassPane(theme)
        .onAppear { model.setShortcutPreset(model.chosenPreset) }
    }
}

struct SystemAudioPanel: View {
    @ObservedObject var model: LabModel
    private var theme: GlassTheme { model.theme }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(model.audioStarting ? "正在连接系统声音…" : model.audioTitle).font(.system(size:12)).foregroundStyle(theme.secondary)
                Spacer()
                Toggle("启用键盘律动",isOn:Binding(get:{ model.musicRequested || model.musicLightingEnabled },set:{ model.setMusicLighting($0) }))
                    .toggleStyle(.switch).controlSize(.regular)
            }
            HStack {
                Text("灵敏度").frame(width:52,alignment:.leading)
                Text("柔和").foregroundStyle(theme.secondary)
                Slider(value:$model.audioSensitivity,in:0.5...2,onEditingChanged:{ _ in model.saveAudioSensitivity() })
                    .accessibilityLabel("节拍灵敏度").help("控制细小节拍的响应与回落速度，不限制柱子的最高位置。")
                Text("敏捷").foregroundStyle(theme.secondary)
                Button("重置") { model.audioSensitivity = 1; model.saveAudioSensitivity() }
            }
            HStack {
                Picker("目标帧率",selection:Binding(get:{ model.motionFPS },set:{ model.setMotionFPS($0) })) {
                    ForEach(LightingRate.choices,id:\.self) { Text("\($0) FPS").tag($0) }
                }.frame(width:210)
                Spacer(); Button("音频授权设置") { model.audioPermissions() }
            }
            if let error = model.audioError { Text(error).font(.system(size:11)).foregroundStyle(theme.warning) }
        }.font(.system(size:12)).padding(20).glassPane(theme)
    }
}
