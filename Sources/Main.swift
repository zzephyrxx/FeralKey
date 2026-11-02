// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

@main
struct FeralKeyApp: App {
    @StateObject private var model = LabModel()
    var body: some Scene {
        WindowGroup("FeralKey") {
            Group {
                if let failure = model.startupError {
                    StartupRecoveryView(message: failure, theme: model.theme)
                } else {
                    LabView(model: model)
                }
            }
                .frame(minWidth: 1080, minHeight: 760)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cleanup() }
                .onOpenURL { model.handleURL($0) }
                .onAppear {
                    if CommandLine.arguments.contains("--render-preview") { renderPreviewIfRequested() }
                    else { model.activate() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("键盘") {
                Button("连接与权限…") { model.connectionSheet = true }
                Button("发送灯光通知") { model.notify() }
                Divider()
                Button("导出配置…") { model.exportProfile() }
                Button("导入配置…") { model.importProfile() }
            }
        }
    }

    // Local visual smoke test: render only our own view, without screen capture.
    private func renderPreviewIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-preview"), args.count > flag+1 else { return }
        if let idx = args.firstIndex(of: "--page"), args.count > idx+1 { model.page = args[idx+1] }
        if let idx = args.firstIndex(of: "--theme"), args.count > idx+1, let theme = GlassTheme(rawValue: args[idx+1]) { model.theme = theme }
        if args.contains("--demo") { model.demoQuota() }
        if args.contains("--quota-layout") { model.quotaLayoutExpanded = true; model.quotaZones = .defaults(layout:model.layout) }
        if args.contains("--quota-only-five") { model.quotaDisplay.weeklyEnabled = false }
        if args.contains("--notification-tab") { model.lightingTab = 1; model.notificationSettings.pattern = .codeRain }
        if args.contains("--motion-demo") { model.basicPattern = .codeRain; model.profile.light.color = .mint }
        if args.contains("--multicolor-demo") { model.profile.light.rainbow = true; model.profile.light.brightness = 5 }
        if args.contains("--audio-demo") {
            model.audioPlaying = true
            model.audioBands = (0..<AudioSpectrumAnalyzer.bandCount).map { i in pow(max(0,sin(Double(i)*0.43)),2)*0.9 }
            model.musicLightingEnabled = true
            model.audioTitle = "频谱律动 · 离线演示"
        }
        if args.contains("--connection-sheet") { DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { model.connectionSheet = true } }
        if args.contains("--risk-sheet") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.riskSheet = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApplication.shared.windows.first?.setContentSize(NSSize(width: 1080, height: args.contains("--tall") ? 1400 : 800)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let windows = NSApplication.shared.windows
            let sheet = windows.compactMap(\.attachedSheet).first
            if args.contains("--risk-sheet") { print("Risk sheet attached: \(sheet != nil)") }
            let target = (args.contains("--risk-sheet") || args.contains("--connection-sheet") || args.contains("--quota-layout")) ? sheet : windows.first(where: { $0.contentView != nil })
            guard let view = target?.contentView else { exit(2) }
            view.layoutSubtreeIfNeeded()
            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
            view.cacheDisplay(in: view.bounds, to: image)
            guard let data = image.representation(using: .png, properties: [:]) else { exit(4) }
            do {
                try data.write(to: URL(fileURLWithPath: args[flag+1]))
                if !args.contains("--keep-preview-open") { exit(0) }
            } catch { exit(5) }
        }
    }
}

struct LabView: View {
    private static let brandLogo: NSImage = Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("FeralKey_logo.png")) } ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage()
    @ObservedObject var model: LabModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var theme: GlassTheme { model.theme }
    let sections = [("Agent额度灯", "chart.bar.xaxis"), ("工作台", "square.grid.2x2"), ("探索向导", "safari"), ("灯效与通知", "lightbulb"), ("按键工作流", "keyboard"), ("音乐实验室", "waveform"), ("研究记录", "doc.text.magnifyingglass")]
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 30) {
                brand.padding(.top, 24)
                VStack(spacing: 8) {
                    ForEach(sections, id: \.0) { title, symbol in
                        Button { model.navigate(title) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: symbol).font(.system(size: 15, weight: .regular)).frame(width: 19)
                                Text(title).font(.system(size: 13, weight: model.page == title ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.82)
                                Spacer()
                                if model.page == title { Circle().fill(theme.accent).frame(width: 4, height: 4) }
                            }.foregroundStyle(model.page == title ? theme.foreground : theme.secondary)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background { if model.page == title { GlassSelection(theme: theme) } }
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                themeSwitcher
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Circle().fill(model.connected ? Color.green.opacity(0.75) : theme.warning).frame(width: 6, height: 6); Text(model.connected ? "RK98 · 已连接" : (model.detected ? "RK98 · USB 已识别" : (model.receiverDetected ? "2.4G · 已识别，暂不支持灯控" : "等待键盘连接"))) }
                    Text("所有设置，留在本机。").font(.system(size: 10)).foregroundStyle(theme.muted)
                }.font(.system(size: 11)).padding(.horizontal, 12).padding(.bottom, 24)
            }.padding(.horizontal, 16).frame(width: 205).frame(maxHeight: .infinity).glassPane(theme, radius: 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switch model.page {
                    case "Agent额度灯": quotaDashboard
                    case "探索向导": discoveryGuide
                    case "灯效与通知": lights
                    case "按键工作流": mapping
                    case "音乐实验室": music
                    case "研究记录": research
                    default: dashboard
                    }
                }.padding(.horizontal, 22).padding(.vertical, 20).frame(maxWidth: 1150, alignment: .leading)
            }
        }.padding(16).padding(.top, 12)
        .background(GlassBackdrop(theme: theme))
        .foregroundStyle(theme.foreground).tint(theme.accent).preferredColorScheme(theme.scheme)
        .buttonStyle(FeralButtonStyle(theme: theme))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.theme)
        .sheet(isPresented: $model.connectionSheet) { ConnectionSettingsView(model:model) }
        .sheet(isPresented: $model.quotaLayoutExpanded) { AgentLayoutView(model:model) }
        .sheet(isPresented: $model.riskSheet) { ResearchConsentView(model: model) }
        .confirmationDialog("确认写入键盘？", isPresented: Binding(get: { model.writePrompt != nil }, set: { if !$0 { model.writePrompt = nil } }), titleVisibility: .visible) {
            Button("确认本次操作") { model.approveWrite() }
            Button("取消", role: .cancel) { model.cancelWrite() }
        } message: { Text(model.writePrompt ?? "") }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        .confirmationDialog("恢复公开默认按键布局？", isPresented: $model.resetConfirm, titleVisibility: .visible) {
            Button("恢复默认映射") { model.resetMapping() }
        } message: { Text("会覆盖全部按键映射。灯光和固件不受影响。") }
    }

    var brand: some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.brandLogo)
                .resizable().scaledToFit().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("FeralKey").font(.system(size: 21, weight: .semibold))
                Text("KEYBOARD STUDIO").font(.system(size: 8, weight: .medium)).tracking(0.7).foregroundStyle(theme.secondary)
            }
        }.padding(.horizontal, 10).accessibilityElement(children: .ignore).accessibilityLabel("FeralKey")
    }
    var themeSwitcher: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("外观").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.muted).padding(.leading, 10)
            HStack(spacing: 4) {
                ForEach(GlassTheme.allCases) { option in
                    Button { model.theme = option } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .foregroundStyle(theme == option ? theme.foreground : theme.secondary)
                            .background { if theme == option { GlassSelection(theme: theme, radius: 20) } }
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("\(option.title)主题").accessibilityAddTraits(theme == option ? [.isSelected] : [])
                }
            }.padding(4).background(theme.foreground.opacity(0.035), in: Capsule()).overlay(Capsule().strokeBorder(theme.edge, lineWidth: 0.5))
        }
    }

    var header: some View {
        HStack { Text(model.page).font(.system(size: 26, weight: .medium)); Spacer(); Button("连接与权限") { model.connectionSheet = true }.font(.system(size:12)) }
    }

    var dashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            card(model.receiverOnly ? "2.4G 接收器" : (model.detected || model.connected ? "RK98" : "等待键盘"), subtitle: model.receiverOnly ? "25A7:FA70 · 灯光控制尚未适配" : (model.connected ? "USB 已连接" : (model.detected ? "已识别 · 尚未连接控制接口" : "连接有线键盘以开始"))) {
                HStack(spacing: 28) {
                    deviceFact("键位", model.receiverOnly ? "型号待确认" : "\(model.layout.keys.count) 键")
                    deviceFact("背光", model.receiverOnly ? "暂未适配" : "RGB · 逐键 / 整板")
                    deviceFact("按键改写", model.receiverOnly ? "暂未适配" : "支持 · Fn 除外")
                    deviceFact("独立宏键", model.receiverOnly ? "未知" : "无")
                    Spacer()
                    if !model.connected { Button("连接与权限") { model.connectionSheet = true } }
                }
                FeralDisclosure("设备详情",theme:theme,symbol:"keyboard") {
                    Text(model.receiverOnly ? "25A7:FA70 是共享接收器编号，不能据此确定键盘型号。已完成接口识别，灯光协议仍待确认；可继续查看屏幕额度。" : "当前适配档案：RK98-100KRGB N · USB 258A:00C1。能力来自已匹配的型号资料，独立宏键依据当前型号配置；并非自动检测所有品牌。")
                        .font(.system(size: 11)).foregroundStyle(theme.secondary)
                }.font(.system(size: 11))
            }
            HStack(alignment: .top, spacing: 14) {
                tile("Agent额度灯", "在指尖查看剩余额度", "chart.bar") { model.navigate("Agent额度灯") }
                tile("灯光与通知", "设置灯效和提醒区域", "lightbulb") { model.navigate("灯效与通知") }
                tile("音乐律动", "跟随正在播放的声音", "waveform") { model.navigate("音乐实验室") }
            }
            FeralDisclosure("布局预览",theme:theme,symbol:"rectangle.grid.3x2") { keyboard }.font(.system(size: 12))
        }
    }
    func deviceFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(theme.secondary)
            Text(value).font(.system(size: 13, weight: .medium))
        }
    }
    func tile(_ title: String, _ subtitle: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: icon).foregroundStyle(theme.accent).font(.system(size: 18))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(theme.muted)
                }
                Text(title).font(.system(size: 15, weight: .medium))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(theme.secondary).lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(20).frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading).glassPane(theme, radius: 19, raised: true)
        }.buttonStyle(.plain)
    }
    var keyboard: some View {
        TimelineView(.animation(minimumInterval: 1.0/Double(model.motionFPS), paused: !model.previewIsAnimated)) { context in
            GeometryReader { geo in
                let sx = (geo.size.width - 32) / 850
                let colors = model.previewColors(time: context.date.timeIntervalSinceReferenceDate)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18).fill(theme.foreground.opacity(theme.isDark ? 0.05 : 0.025))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.edge, lineWidth: 0.5))
                    ForEach(model.layout.keys) { key in
                        Button { model.selectKey(key) } label: {
                            KeyCap(key: key, scale: sx, color: keyTint(colors[key.id] ?? QuotaRenderer.off), selected: model.keySelectedInPreview(key.id), changed: model.profile.overrides[key.id] != nil, level: 0, theme: theme, quotaMode: true, badge: model.page == "Agent额度灯" ? model.quotaMarker(key.id) : nil)
                        }.buttonStyle(.plain).position(x: 16 + CGFloat(key.top[0] + key.bottom[0])/2*sx, y: 12 + CGFloat(key.top[1] + key.bottom[1])/2*sx)
                    }
                }
            }.aspectRatio(850.0/310.0, contentMode: .fit)
        }.accessibilityLabel("键盘灯光预览")
    }
    func rgbColor(_ rgb: RGB) -> Color {
        Color(red: Double(rgb.r)/255, green: Double(rgb.g)/255, blue: Double(rgb.b)/255)
    }
    func keyTint(_ rgb: RGB) -> Color { rgb == QuotaRenderer.off ? .clear : rgbColor(rgb) }
    var lights: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("设置", selection: $model.lightingTab) { Text("基础灯效").tag(0); Text("通知").tag(1) }
                .pickerStyle(.segmented).frame(width: 300)
            keyboard
            if model.lightingTab == 0 { basicLights }
            else {
                NotificationEditor(model: model)
                FeralDisclosure("系统通知与专注",theme:theme,symbol:"bell") {
                    SystemNotificationPanel(model: model)
                    HStack {
                        Stepper("专注 \(model.focusMinutes) 分钟", value: $model.focusMinutes, in: 1...120)
                        Spacer()
                        Button(model.remaining > 0 ? "停止计时" : "开始专注") { model.remaining > 0 ? model.stopFocus() : model.startFocus() }.disabled(!model.connected || !model.appliedLight)
                    }.padding(.top, 10)
                }.font(.system(size: 12)).padding(18).glassPane(theme)
            }
        }
    }
    var basicLights: some View {
        card("基础灯效", subtitle: "") {
            HStack(spacing: 20) {
                Picker("模式", selection: Binding(get: { model.basicPattern }, set: { model.setBasePattern($0) })) {
                    ForEach(BasicPattern.allCases.filter { $0 != .rain || model.basicPattern == .rain }) { Text($0.title).tag($0) }
                }.frame(width: 190)
                ColorPicker("颜色", selection: Binding(get: { rgbColor(model.profile.light.color) }, set: { value in
                    let c = NSColor(value).usingColorSpace(.deviceRGB) ?? .white
                    model.setBaseColor(RGB(r: UInt8(min(255,max(0,c.redComponent*255))), g: UInt8(min(255,max(0,c.greenComponent*255))), b: UInt8(min(255,max(0,c.blueComponent*255)))))
                }), supportsOpacity: false).disabled(model.profile.light.rainbow)
                Spacer()
                Button("应用基础灯效") { model.applyLight() }
                    .buttonStyle(FeralButtonStyle(theme: theme, prominent: true)).disabled(!model.connected)
            }
            HStack {
                Picker("配色",selection:$model.profile.light.rainbow) { Text("单色").tag(false); Text("多彩").tag(true) }.pickerStyle(.segmented).frame(width:220)
                Spacer()
            }.font(.system(size:12))
            HStack(spacing: 18) {
                Text("亮度"); Slider(value: Binding(get: { Double(model.profile.light.brightness) }, set: { model.profile.light.brightness = UInt8($0) }), in: 0...5, step: 1)
                if model.basicPattern.motion != nil {
                    Text("速度"); Slider(value: Binding(get: { Double(model.profile.light.speed) }, set: { model.profile.light.speed = UInt8($0) }), in: 1...5, step: 1)
                }
            }.font(.system(size: 12))
            if model.basicPattern.motion != nil { Text("多彩和动态灯效均保留已应用的额度区。").font(.system(size: 11)).foregroundStyle(theme.secondary) }
            if model.lightingActive { Text(model.motionStatus).font(.system(size:11)).foregroundStyle(theme.secondary) }

        }
    }

    var targets: [(String, UInt32)] {
        [("⌘C · 复制", 0x080600), ("⌘V · 粘贴", 0x081900), ("⌘X · 剪切", 0x081b00), ("⌘S · 保存", 0x081600), ("⌘Z · 撤销", 0x081d00), ("⌃⌥⌘1 · 本工具工作流", 0x0d1e00)] + model.layout.keys.filter { $0.keyCode != "Key_Fn" }.compactMap { key in model.codes[key.keyCode].map { (key.label + " · " + key.keyCode.replacingOccurrences(of: "Key_", with: ""), $0) } }
    }
    var mapping: some View {
        VStack(alignment: .leading, spacing: 22) {
            keyboard
            ShortcutEditor(model: model)
            HStack {
                Text("已修改 \(model.profile.overrides.count) 个按键").font(.system(size: 12)).foregroundStyle(theme.secondary)
                Spacer()
                Button("应用到键盘…") { model.applyMapping() }.disabled(!model.connected || model.profile.overrides.isEmpty)
            }
            FeralDisclosure("普通按键与现有映射",theme:theme,symbol:"keyboard") {
            card("现有映射与普通按键", subtitle: "将完整 100 键默认布局与下方修改一起写入键盘；会覆盖已有自定义映射。Fn 层由固件管理。") {
                HStack {
                    Text(model.layout.keys.first { $0.id == model.selectedKey }?.label ?? "未选择按键").font(.system(size: 18, weight: .semibold)).frame(width: 110, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(theme.accent)
                    Picker("目标", selection: $model.targetCode) { ForEach(Array(targets.enumerated()), id: \.offset) { _, item in Text(item.0).tag(item.1) } }.frame(maxWidth: 360)
                    Button("加入修改") { model.stageMapping() }.disabled(model.selectedKey == nil || model.layout.keys.first { $0.id == model.selectedKey }?.keyCode == "Key_Fn")
                }
                ForEach(model.profile.overrides.keys.sorted(), id: \.self) { idx in
                    HStack {
                        Text(model.layout.keys.first { $0.id == idx }?.label ?? "?")
                        Image(systemName: "arrow.right").foregroundStyle(theme.secondary)
                        Text(model.mappingTitle(model.profile.overrides[idx] ?? 0)).foregroundStyle(theme.accent)
                        Spacer()
                        Button("移除") { model.profile.overrides.removeValue(forKey: idx); model.save() }
                    }.font(.system(size: 12))
                }
                HStack {
                    Button("恢复默认按键…") { model.resetConfirm = true }.disabled(!model.connected)
                    Spacer()
                    Button("将完整映射应用到键盘") { model.applyMapping() }.buttonStyle(FeralButtonStyle(theme: theme, prominent: true)).disabled(!model.connected)
                }
            }
            }
            FeralDisclosure("自定义工作流",theme:theme,symbol:"bolt") {
            card("自定义工作流", subtitle: "启用后，⌃⌥⌘1 在所有键盘上生效。可把上方一个闲置键映射到此组合键，实现单键触发。") {
                HStack {
                    Picker("执行", selection: $model.workflow) { ForEach(["灯光通知", "专注计时", "打开网址", "运行快捷指令"], id: \.self) { Text($0) } }.frame(width: 250)
                    Spacer()
                    Button(model.hotkeysEnabled || model.preferredHotkeys ? "关闭快捷键" : "启用快捷键") { model.setHotkeyEnabled(!model.hotkeysEnabled && !model.preferredHotkeys) }
                    Button("立即执行") { model.runWorkflow() }
                }
                if model.workflow == "打开网址" { TextField("https://…", text: $model.profile.shortcutURL).textFieldStyle(.roundedBorder) }
                if model.workflow == "运行快捷指令" { TextField("macOS「快捷指令」中的名称", text: $model.profile.shortcutName).textFieldStyle(.roundedBorder) }
            }
            }
            HStack { Button("导出配置…") { model.exportProfile() }; Button("导入配置…") { model.importProfile() }; Text("导入只更新界面，需要手动应用。").font(.system(size: 11)).foregroundStyle(theme.secondary) }
        }
    }

    var music: some View {
        VStack(alignment: .leading, spacing: 16) {
            keyboard
            SystemAudioPanel(model: model)
        }
    }

    var research: some View {
        VStack(alignment: .leading, spacing: 22) {
            card("已确认与待验证", subtitle: "区分系统识别、公开协议与实物验证。") {
                fact("已确认", "USB 设备 258A:00C1，厂商 SINO WEALTH，系统名称 Bluetooth Keyboard。")
                fact("已确认", "控制接口 usage 0x80 / page 0x01，Feature Report ID 0x0A，65 字节。")
                fact("来源匹配", "Rangoli 明确收录 RK98-100KRGB N，公开布局含 100 个键位。")
                fact("待验证", "灯效颜色、模式、完整改键，以及通知后的实物恢复效果。")
                fact("连接", model.connected ? "当前控制接口已打开。" : "尚未打开控制接口；如出现 0xe00002e2，请按权限排查文档更新授权。")
                fact("未知", "没有已验证的原灯效读取/备份方式；没有确认 RAM 专用灯光流。")
            }
            card("操作记录", subtitle: "只记录连接与配置操作；不记录输入文字。") {
                ForEach(Array(model.log.enumerated()), id: \.offset) { _, row in Text(row).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.secondary).textSelection(.enabled) }
            }
            HStack {
                Link("Rangoli 协议来源 ↗", destination: URL(string:"https://github.com/rnayabed/rangoli")!)
                Link("Kludge Knight 交叉核对 ↗", destination: URL(string:"https://github.com/vinc3m1/kludgeknight")!)
            }.font(.system(size: 12))
            Text("本工具仅匹配这一设备编号，不刷写固件。协议与布局基于 GPLv3 开源项目，详情见项目中的 THIRD_PARTY.md。") .font(.system(size: 11)).foregroundStyle(theme.secondary)
        }
    }
    func fact(_ label: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 15) { Text(label).foregroundStyle(theme.accent).frame(width: 65, alignment: .leading); Text(detail).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true) }.font(.system(size: 12))
    }
    func card<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(title).font(.system(size: 17, weight: .semibold))
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true) }
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).glassPane(theme, radius: 20)
    }
}

struct StartupRecoveryView: View {
    let message: String
    let theme: GlassTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("FeralKey 无法加载应用资源", systemImage: "exclamationmark.triangle").font(.system(size: 24, weight: .semibold))
            Text("应用文件可能不完整或已损坏。请重新下载完整应用，或重新构建后打开。设备配置已停用。")
                .font(.system(size: 14)).foregroundStyle(theme.secondary)
            Text(message).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("显示应用位置") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Button("退出 FeralKey") { NSApplication.shared.terminate(nil) }
            }.buttonStyle(FeralButtonStyle(theme: theme))
        }.padding(36).frame(maxWidth: 720, alignment: .leading).glassPane(theme)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(GlassBackdrop(theme: theme))
            .foregroundStyle(theme.foreground).preferredColorScheme(theme.scheme)
    }
}

struct KeyCap: View {
    let key: PhysicalKey
    let scale: CGFloat
    let color: Color
    let selected: Bool
    let changed: Bool
    let level: Double
    let theme: GlassTheme
    var quotaMode = false
    var badge: String? = nil
    private var legend: some View {
        VStack(spacing:1) {
            Text(key.label).font(.system(size:max(7,10*scale),weight:.medium,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.5)
            if let badge { Text(badge).font(.system(size:max(6,7*scale),weight:.semibold,design:.rounded)).lineLimit(1) }
        }
    }
    var body: some View {
        let border: Color = selected ? theme.accent.opacity(0.65) : (changed ? theme.warning : theme.edge)
        let fill: Color = selected ? theme.accent.opacity(0.16) : theme.keyFill
        let width: CGFloat = max(8, CGFloat(key.bottom[0]-key.top[0])*scale)
        let height: CGFloat = max(10, CGFloat(key.bottom[1]-key.top[1])*scale)
        legend
            .frame(width: width, height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).fill(color.opacity(quotaMode ? 0.52 : 0.045 + level * 0.25)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(border, lineWidth: 0.6))
            .overlay(RoundedRectangle(cornerRadius: 5).inset(by: 0.7).strokeBorder(LinearGradient(colors: [theme.rim.opacity(0.7), .clear], startPoint: .top, endPoint: .center), lineWidth: 0.6))
            .shadow(color: .black.opacity(theme.isDark ? 0.10 : 0.045), radius: 1.5, x: 0, y: 1.5)
            .foregroundStyle(changed ? theme.warning : theme.foreground.opacity(0.85))
    }
}
