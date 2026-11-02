// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

extension LabView {
    var quotaDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                quotaCard("五小时", minutes: 300, weekly: false)
                quotaCard("每周", minutes: 10080, weekly: true)
            }
            quotaSourceRow
            if let error = model.quotaError { Text(error).font(.system(size: 11)).foregroundStyle(theme.warning) }
            AgentPaletteEditor(model: model)
            HStack {
                Toggle("自动同步实体灯条", isOn: Binding(get: { model.quotaHardwareAuto || model.preferredHardwareAuto }, set: { model.setQuotaHardwareAuto($0) }))
                    .disabled((!model.canSyncQuota || model.agentNeedsApply) && !model.quotaHardwareAuto && !model.preferredHardwareAuto)
                Spacer()
                if !model.connected { Button("连接与权限") { model.connectionSheet = true } }
                Text(model.agentNeedsApply ? "待应用" : "已应用").font(.system(size:11)).foregroundStyle(theme.secondary)
            }.font(.system(size: 12)).padding(16).glassPane(theme)
            Button("配置灯条按键 · 每键 10%") { model.quotaLayoutExpanded = true }.font(.system(size: 12))
            FeralDisclosure("数据源与状态",theme:theme,symbol:"chart.bar.xaxis") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(CodexClient.locate(override: model.codexPath) == nil ? "未找到 Codex" : "本机 Codex 已就绪")
                        Spacer(); Button("选择 Codex…") { model.chooseCodex() }
                    }
                    Text(model.lastPhysicalSync.map { "实体上次发送：" + $0.formatted(date: .omitted, time: .standard) } ?? "实体尚未同步")
                    Text("读取失败保留实体最后快照；屏幕显示未知。灰色表示未知，演示数据不会写入键盘。")
                }.font(.system(size: 11)).foregroundStyle(theme.secondary).padding(.top, 10)
            }.font(.system(size: 12))
        }
    }
    func quotaCard(_ title: String, minutes: Int, weekly: Bool) -> some View {
        let remaining = model.quotaRemaining(minutes)
        let rgb = QuotaRenderer.color(remaining: remaining ?? 100, weekly: weekly, palette: model.agentPalette)
        let tint = Color(red: Double(rgb.r)/255, green: Double(rgb.g)/255, blue: Double(rgb.b)/255)
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Toggle(title + "灯",isOn:Binding(get:{ weekly ? model.quotaDisplay.weeklyEnabled : model.quotaDisplay.fiveHourEnabled },set:{ if weekly { model.quotaDisplay.weeklyEnabled = $0 } else { model.quotaDisplay.fiveHourEnabled = $0 } })).font(.system(size:13,weight:.medium))
                Spacer()
                Text("剩余额度").font(.system(size: 10)).foregroundStyle(theme.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(remaining.map { String(format: "%.0f", $0) } ?? "—").font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                Text(remaining == nil ? "状态未知" : "%").font(.system(size: 13)).foregroundStyle(theme.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.foreground.opacity(0.07))
                    Capsule().fill(remaining == nil ? theme.muted : tint).frame(width: geometry.size.width * CGFloat((remaining ?? 0) / 100))
                }
            }.frame(height: 6)
            HStack {
                ColorPicker("灯色",selection:Binding(get:{
                    let c = weekly ? model.agentPalette.weekly : model.agentPalette.fiveHour
                    return Color(red:Double(c.r)/255,green:Double(c.g)/255,blue:Double(c.b)/255)
                },set:{ value in
                    let c = NSColor(value).usingColorSpace(.deviceRGB) ?? .white
                    let rgb = RGB(r:UInt8(min(255,max(0,c.redComponent*255))),g:UInt8(min(255,max(0,c.greenComponent*255))),b:UInt8(min(255,max(0,c.blueComponent*255))))
                    if weekly { model.agentPalette.weekly = rgb } else { model.agentPalette.fiveHour = rgb }
                }),supportsOpacity:false).font(.system(size:11))
                Spacer()
            }
            Text(quotaResetText(minutes)).font(.system(size:10)).foregroundStyle(theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).glassPane(theme, radius: 20, raised: true)
    }
    func quotaResetText(_ minutes: Int) -> String {
        guard let timestamp = model.quota?.buckets[model.quotaBucket]?.window(minutes: minutes)?.resetsAt else { return "等待 Codex 返回重置时间" }
        if timestamp <= model.quotaNow.timeIntervalSince1970 { return "已到重置时间 · 等待重新读取" }
        return "重置于 " + Date(timeIntervalSince1970: timestamp).formatted(date: .abbreviated, time: .shortened)
    }
    var quotaSourceRow: some View {
        HStack(spacing: 12) {
            Button(model.quotaLoading ? "读取中…" : (model.quota?.isDemo == true ? "退出演示并刷新" : "刷新额度")) { if model.quota?.isDemo == true { model.startQuota() } else { model.refreshQuota() } }.disabled(model.quotaLoading)
            Button("演示") { model.demoQuota() }
            Toggle("自动刷新", isOn: Binding(get: { model.quotaAutoRefresh }, set: { $0 ? model.startQuota() : model.stopQuota() })).toggleStyle(.switch).controlSize(.small)
            Picker("间隔", selection: Binding(get: { model.quotaInterval }, set: { model.setQuotaInterval($0) })) {
                ForEach(RefreshSchedule.intervals, id: \.self) { Text(RefreshSchedule.title($0)).tag($0) }
            }.frame(width: 150)
            Spacer()
            if let quota = model.quota {
                if quota.buckets.count > 1 {
                    Picker("额度池", selection: $model.quotaBucket) {
                        Text("请选择").tag("")
                        ForEach(quota.buckets.keys.sorted(), id: \.self) { key in Text(quota.buckets[key]?.limitName ?? key).tag(key) }
                    }.frame(maxWidth: 220)
                }
                Text((quota.isDemo ? "演示生成于 " : "读取于 ") + quota.fetchedAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 10)).foregroundStyle(theme.secondary)
            }
        }
    }
    var quotaControls: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker("配置灯条",selection:$model.quotaEditing) { Text("五小时").tag(1); Text("每周").tag(2) }.pickerStyle(.segmented).frame(width:260)
                Spacer(); Button("恢复默认键位") { model.resetQuotaZones() }
            }
            HStack(spacing:5) {
                ForEach(0..<10) { index in
                    let keys = model.quotaEditing == 2 ? model.quotaZones.weekly : model.quotaZones.fiveHour
                    Button { model.quotaSlot = index } label: {
                        VStack(spacing:4) {
                            Text("\((index+1)*10)%").font(.system(size:11,weight:.semibold))
                            Text(model.layout.keys.first { $0.id == keys[index] }?.label ?? "—").font(.system(size:10,design:.monospaced))
                        }.frame(maxWidth:.infinity).padding(.vertical,9)
                            .background(model.quotaSlot == index ? theme.accent.opacity(0.22) : theme.keyFill,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Text("先选百分比，再点按键；占用键交换位置，每颗代表 10%。").font(.system(size:11)).foregroundStyle(theme.secondary)
                Spacer(); Button("应用配置") { model.applyAgentFromEditor() }.disabled(!model.canApplyAgent)
            }
        }.padding(.top,10)
    }
    func quotaKeyNames(_ ids: [Int]) -> String { ids.map { id in model.layout.keys.first { $0.id == id }?.label ?? "?" }.joined(separator: " · ") }

    var discoveryGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("识别你的键盘", subtitle: "先识别，再按适配教程验证。") {
                HStack {
                    Button("风险须知") { model.riskChecked = false; model.riskSheet = true }
                    Button("扫描设备") { model.refreshDiscovery() }
                    Spacer()
                    Button("导出研究包…") { model.exportResearch() }.disabled(!model.riskAccepted || model.discovered.isEmpty)
                }
                ForEach(model.discovered) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.product).font(.system(size: 13, weight: .medium))
                            Text("\(device.identifier) · \(device.transport)").font(.system(size: 11)).foregroundStyle(theme.secondary)
                        }
                        Spacer()
                        Text(device.matchesRK98Control ? "有实验适配" : "仅识别").font(.system(size: 11)).foregroundStyle(theme.secondary)
                    }.padding(.vertical, 5)
                }
                if model.discovered.isEmpty { Text("扫描后显示设备及适配状态。").font(.system(size: 12)).foregroundStyle(theme.secondary) }
            }
            FeralDisclosure("如何适配与测试",theme:theme,symbol:"book") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("当前只开放匹配的 RK98 USB 适配。其他设备先导出接口资料、核对公开协议，不尝试未知命令。研究包不是原配置备份。")
                    HStack {
                        Button("输入监控设置") { model.permissions() }
                        Button("连接 RK98") { model.connect() }.disabled(!model.riskAccepted)
                        if let tutorial = Bundle.main.resourceURL?.appendingPathComponent("Docs/KEYBOARD-GUIDE.md") { Link("完整教程", destination: tutorial) }
                    }
                }.font(.system(size: 12)).padding(.top, 10)
            }.font(.system(size: 12)).padding(18).glassPane(theme)
        }
    }

}

struct AgentLayoutView: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("额度灯键位 · 每颗 10%").font(.system(size:20,weight:.semibold)); Spacer(); Button("完成") { dismiss() } }
            LabView(model:model).quotaControls
            LabView(model:model).keyboard
        }.padding(24).frame(width:950)
            .background(GlassBackdrop(theme:model.theme)).foregroundStyle(model.theme.foreground)
            .buttonStyle(FeralButtonStyle(theme:model.theme)).preferredColorScheme(model.theme.scheme)
    }
}

struct ResearchConsentView: View {
    @ObservedObject var model: LabModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("实验功能与风险须知", systemImage: "exclamationmark.shield").font(.system(size: 22, weight: .semibold))
            ScrollView { Text(ResearchNotice.text).font(.system(size: 13)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 320)
            Toggle("我已阅读、理解并自愿承担上述操作风险", isOn: $model.riskChecked).font(.system(size: 12))
            HStack {
                Text("第 1 版 · 仅保存本机确认状态").font(.system(size: 10)).foregroundStyle(model.theme.secondary)
                Spacer()
                Button("暂不进入") { model.riskSheet = false }
                Button("同意并继续") { model.acceptResearchRisk() }.disabled(!model.riskChecked).buttonStyle(FeralButtonStyle(theme: model.theme, prominent: true))
            }
        }.padding(30).frame(width: 610).background(GlassBackdrop(theme: model.theme)).foregroundStyle(model.theme.foreground)
            .buttonStyle(FeralButtonStyle(theme: model.theme)).preferredColorScheme(model.theme.scheme).interactiveDismissDisabled()
    }
}
