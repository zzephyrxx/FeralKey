// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import AVFoundation
import Carbon
import IOKit.hidsystem
import IOKit.hid
import Combine

final class LabModel: ObservableObject {
    @Published var page = "Agent额度灯"
    @Published var quota: QuotaSnapshot?
    @Published var quotaError: String?
    @Published var quotaLoading = false
    @Published var quotaAutoRefresh = false
    @Published var quotaInterval = 60
    @Published var nextQuotaRefresh: Date?
    @Published var quotaHardwareAuto = false
    @Published var agentPalette = AgentPalette()
    @Published var agentPinned = false
    @Published var separateNotificationRegion = false // legacy preference; idle notification keys now follow the base
    private var firmwareMode = false
    @Published var connectionSheet = false
    @Published var autoConnect = true
    @Published var restoreOnConnect = true
    @Published var preferredAgentPinned = false
    @Published var preferredHardwareAuto = false
    @Published var preferredNotifications = false
    @Published var preferredDynamicNotifications = false
    @Published var preferredHotkeys = false
    private var settingObservers = Set<AnyCancellable>()
    @Published var basicPattern: BasicPattern = .solid
    @Published var systemNotificationsEnabled = false
    @Published var systemNotificationStatus = "未开启系统横幅监听"
    @Published var lastSystemBanner: Date?
    private var bannerMonitor: SystemBannerMonitor?
    private var baseColors: [Int: RGB]?
    private var pinnedAgentKeys = Set<Int>()
    private var pinnedAgentColors: [Int: RGB] = [:]
    private var activeNoticeColors: [Int: RGB]?
    @Published var notificationSettings = NotificationSettings(keys: [])
    @Published var notificationEditing = false
    @Published var notificationPreview = true
    @Published var shortcutKey = "Key_C"
    @Published var shortcutModifiers: UInt8 = 8
    @Published var chosenPreset = "pasteStyle"
    @Published var audioStarting = false
    @Published var audioError: String?
    private var activated = false
    private var lastQuotaFrame: [Int: RGB]?
    private var lastQuotaWrite: TimeInterval?
    private var appliedReports: [[UInt8]]?
    private var appliedColors: [Int: RGB]?
    private var systemAudio: SystemAudioCapture?
    private var audioGeneration = 0
    private var audioDecayTimer: Timer?
    private var lastAudioSample: TimeInterval = 0
    private let quotaWriteClock: () -> TimeInterval
    private let lightingClock: () -> TimeInterval
    @Published var quotaBucket = "codex"
    @Published var quotaZones = QuotaZones(fiveHour: [], weekly: [])
    @Published var quotaEditing = 1
    @Published var quotaSlot = 0
    @Published var quotaLayoutExpanded = false
    @Published var quotaDisplay = AgentDisplay()
    private var activeAgent = AgentConfiguration(zones:QuotaZones(fiveHour:[],weekly:[]))
    @Published var agentConfigurationStatus = ""
    @Published var quotaNow = Date()
    @Published var codexPath = ""
    @Published var lastPhysicalSync: Date?
    @Published var discovered: [DeviceDescriptor] = []
    @Published var riskAccepted = false
    @Published var riskSheet = false
    @Published var riskChecked = false
    @Published var writePrompt: String?
    private var pendingWrite: (() -> Void)?
    private var quotaTimer: Timer?
    private var quotaClock: Timer?
    private var quotaGeneration = 0
    private var quotaCancellation = CodexReadCancellation()
    @Published var profile = LabProfile()
    @Published var status = "尚未连接控制接口"
    @Published var detected = false
    @Published var receiverDetected = false
    @Published var connected = false
    @Published var error: String?
    @Published var log: [String] = []
    @Published var selectedKey: Int?
    @Published var targetCode: UInt32 = 0x080600
    @Published var appliedLight = false
    @Published var notificationActive = false
    @Published var remaining: Int = 0
    @Published var focusMinutes = 25
    @Published var audioLevel: Double = 0
    @Published var audioBands = [Double](repeating:0,count:AudioSpectrumAnalyzer.bandCount)
    @Published var audioSensitivity = 1.0
    private var audioReactor = AudioSpectrumReactor()
    @Published var lightingTab = 0
    @Published var dynamicNotificationsEnabled = false
    @Published var motionFPS = LightingRate.defaultFPS
    @Published var directStreamEnabled = false
    @Published var musicLightingEnabled = false
    @Published private(set) var musicRequested = false
    private var activeBasePattern: BasicPattern = .solid
    private var baseReports: [[UInt8]]?
    private var agentRestoredThisSession = false
    @Published private(set) var lightingActive = false
    @Published private(set) var motionStatus = ""
    @Published private(set) var motionFramesWritten = 0
    private var motionTimer: Timer?
    private var motionStarted: TimeInterval = 0
    private var motionKind = "base"
    private var motionNotice = NotificationSettings(keys: [])
    private var lastMotionFrame: [Int: RGB]?
    private var lastMotionWrite: TimeInterval?
    private var lastMotionSubmitted: TimeInterval?
    private var liveGeneration = 0
    private var liveInFlight = false
    private var activeMotionFPS = LightingRate.defaultFPS
    private var notificationStarted: TimeInterval = 0
    @Published var audioPlaying = false
    @Published var audioTitle = "未启用 · 等待手动开启"
    @Published var hotkeysEnabled = false
    @Published var workflow: String = "灯光通知"
    @Published var resetConfirm = false
    @Published var theme: GlassTheme = .daylight {
        didSet {
            if !CommandLine.arguments.contains("--render-preview") { preferences.set(theme.rawValue, forKey: "appearance") }
        }
    }
    let hid: KeyboardTransport
    private let preferences: UserDefaults
    @Published private(set) var startupError: String?
    private var connectionGeneration = 0
    private var notificationGeneration = 0
    private var lastNotificationAt: TimeInterval?
    var resourcesReady: Bool { startupError == nil }
    let layout: Layout
    let codes: [String: UInt32]
    private var appliedSettings = LightSettings()
    private var notificationReturn: DispatchWorkItem?
    private var focusTimer: Timer?
    private var focusDeadline: Date?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(resourceRoot: URL? = Bundle.main.resourceURL, preferences: UserDefaults = .standard, transport: KeyboardTransport = KeyboardHID(), enumerateOnStart: Bool = true, quotaWriteClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, lightingClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.quotaWriteClock = quotaWriteClock
        self.lightingClock = lightingClock
        self.preferences = preferences
        self.hid = transport
        if let stored = preferences.string(forKey: "appearance"), let saved = GlassTheme(rawValue: stored) { theme = saved }
        do {
            guard let root = resourceRoot else { throw RKError.message("找不到应用资源目录。") }
            let loadedLayout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: root.appendingPathComponent("rk98-layout.json")))
            let loadedCodes = try JSONDecoder().decode([String: UInt32].self, from: Data(contentsOf: root.appendingPathComponent("keycodes.json")))
            try loadedLayout.validate(codes: loadedCodes)
            layout = loadedLayout; codes = loadedCodes
        } catch {
            layout = Layout(name: "资源不可用", keys: []); codes = [:]
            startupError = "应用资源缺失或损坏，请重新安装完整应用。开发者可重新运行 scripts/build.sh。"
        }
        if let data = preferences.data(forKey: "agentPalette"), let palette = try? JSONDecoder().decode(AgentPalette.self, from: data) { agentPalette = palette }
        separateNotificationRegion = false
        autoConnect = preferences.object(forKey: "autoConnect") as? Bool ?? true
        restoreOnConnect = preferences.object(forKey: "restoreOnConnect") as? Bool ?? true
        preferredAgentPinned = preferences.bool(forKey: "preferredAgentPinned")
        preferredHardwareAuto = preferences.bool(forKey: "preferredHardwareAuto")
        preferredNotifications = preferences.bool(forKey: "preferredNotifications")
        preferredDynamicNotifications = preferences.bool(forKey: "preferredDynamicNotifications")
        preferredHotkeys = preferences.bool(forKey: "preferredHotkeys")
        let savedFPS = preferences.integer(forKey:"motionFPS")
        let rateVersion = preferences.integer(forKey:"liveSettingsVersion")
        if LightingRate.choices.contains(savedFPS) {
            motionFPS = rateVersion < 2 && savedFPS == 30 ? LightingRate.defaultFPS : savedFPS
        }
        if resourcesReady && !CommandLine.arguments.contains("--render-preview") {
            preferences.set(2,forKey:"liveSettingsVersion"); preferences.set(motionFPS,forKey:"motionFPS")
        }
        if let raw = preferences.string(forKey: "basicPattern"), let pattern = BasicPattern(rawValue: raw) { basicPattern = pattern }
        if let bucket = preferences.string(forKey:"quotaBucket"), bucket != "demo", bucket.count <= 128 { quotaBucket = bucket }
        notificationSettings = .defaults(layout)
        if let data = preferences.data(forKey: "notificationSettings"), let saved = try? JSONDecoder().decode(NotificationSettings.self, from: data), (try? saved.validate(layout)) != nil { notificationSettings = saved }
        let interval = preferences.integer(forKey: "quotaInterval")
        if RefreshSchedule.intervals.contains(interval) { quotaInterval = interval }
        let sensitivity = preferences.double(forKey: "audioSensitivity")
        if (0.5...2).contains(sensitivity) { audioSensitivity = sensitivity }
        quotaZones = QuotaZones.defaults(layout: layout)
        if let data = preferences.data(forKey: "quotaZones"), let zones = try? JSONDecoder().decode(QuotaZones.self, from: data) {
            quotaZones = preferences.integer(forKey:"agentLayoutVersion") < 2 ? QuotaZones.migrated(zones,layout:layout) : ((try? zones.validate(layout:layout)) != nil ? zones : quotaZones)
        }
        if let data = preferences.data(forKey:"quotaDisplay"), let display = try? JSONDecoder().decode(AgentDisplay.self,from:data) { quotaDisplay = display }
        activeAgent = AgentConfiguration(zones:quotaZones,palette:agentPalette,display:quotaDisplay)
        if let data = preferences.data(forKey:"appliedAgentConfiguration"), let config = try? JSONDecoder().decode(AgentConfiguration.self,from:data), (try? config.zones.validate(layout:layout)) != nil { activeAgent = config }
        else if resourcesReady && !CommandLine.arguments.contains("--render-preview"), let data = try? JSONEncoder().encode(activeAgent) { preferences.set(data,forKey:"appliedAgentConfiguration") }
        directStreamEnabled = preferences.integer(forKey:"liveProtocolConsent") == 1
        codexPath = preferences.string(forKey: "codexPath") ?? ""
        riskAccepted = preferences.integer(forKey: "researchConsentVersion") == ResearchNotice.version
        hid.writesAuthorized = riskAccepted
        if let data = preferences.data(forKey: "labProfile") {
            if data.count <= LabProfile.maximumFileBytes, let p = try? JSONDecoder().decode(LabProfile.self, from: data), (try? p.validate(layout: layout, codes: codes)) != nil { profile = p; workflow = p.workflow ?? "灯光通知" }
            else { record("本机配置无效，已使用软件默认配置；没有写入键盘") }
        }
        if let storedPage = preferences.string(forKey: "page"), ["Agent额度灯","工作台","探索向导","灯效与通知","按键工作流","音乐实验室","研究记录"].contains(storedPage) { page = storedPage }
        lightingTab = preferences.integer(forKey: "lightingTab") == 1 ? 1 : 0
        let savedFocus = preferences.integer(forKey: "focusMinutes")
        if (1...120).contains(savedFocus) { focusMinutes = savedFocus }
        if let key = preferences.string(forKey: "shortcutKey"), (try? ShortcutCode.encode(key: key, modifiers: 0, codes: codes)) != nil { shortcutKey = key }
        let flags = preferences.integer(forKey: "shortcutModifiers")
        if preferences.object(forKey: "shortcutModifiers") != nil && (0...15).contains(flags) { shortcutModifiers = UInt8(flags) }
        if let preset = preferences.string(forKey: "chosenPreset"), preset == "custom" || ShortcutPreset.all.contains(where: { $0.id == preset }) { chosenPreset = preset }
        if preferences.object(forKey: "notificationPreview") != nil { notificationPreview = preferences.bool(forKey: "notificationPreview") }
        observeUserSettings()
        if enumerateOnStart && resourcesReady { scan() }
        record("启动：识别有线键盘及 2.4G 接收器；不监听或记录输入内容")
    }

    func record(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.insert("\(time)  \(message)", at: 0)
        if log.count > 100 { log.removeLast() }
    }
    var inputPermissionGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    var accessibilityPermissionGranted: Bool { SystemBannerMonitor.hasPermission }
    var audioPermissionGranted: Bool { audioPlaying || CGPreflightScreenCaptureAccess() }
    func revealApplication() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

    private func observeSetting<T: Encodable>(_ publisher: Published<T>.Publisher) {
        publisher.compactMap { try? JSONEncoder().encode($0) }.removeDuplicates().dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persistUserSettings() }.store(in: &settingObservers)
    }
    private func observeUserSettings() {
        guard !CommandLine.arguments.contains("--render-preview") else { return }
        observeSetting($profile); observeSetting($basicPattern)
        observeSetting($agentPalette); observeSetting($notificationSettings); observeSetting($quotaZones)
        observeSetting($page); observeSetting($lightingTab); observeSetting($focusMinutes)
        observeSetting($shortcutKey); observeSetting($shortcutModifiers); observeSetting($chosenPreset)
        observeSetting($workflow); observeSetting($notificationPreview); observeSetting($audioSensitivity)
        observeSetting($motionFPS); observeSetting($autoConnect); observeSetting($restoreOnConnect)
        observeSetting($quotaBucket); observeSetting($quotaDisplay)
        observeSetting($preferredAgentPinned); observeSetting($preferredHardwareAuto)
        observeSetting($preferredNotifications); observeSetting($preferredDynamicNotifications); observeSetting($preferredHotkeys)
    }
    func persistUserSettings() {
        guard resourcesReady, !CommandLine.arguments.contains("--render-preview") else { return }
        save(); saveAgentPalette(); saveNotification(); saveLightingRegions()
        if let data = try? JSONEncoder().encode(quotaZones), (try? quotaZones.validate(layout: layout)) != nil { preferences.set(data, forKey: "quotaZones") }
        for (key,value) in ["autoConnect":autoConnect,"restoreOnConnect":restoreOnConnect,"preferredAgentPinned":preferredAgentPinned,"preferredHardwareAuto":preferredHardwareAuto,"preferredNotifications":preferredNotifications,"preferredDynamicNotifications":preferredDynamicNotifications,"preferredHotkeys":preferredHotkeys,"notificationPreview":notificationPreview] { preferences.set(value,forKey:key) }
        preferences.set(page,forKey:"page"); preferences.set(lightingTab,forKey:"lightingTab"); preferences.set(focusMinutes,forKey:"focusMinutes")
        preferences.set(shortcutKey,forKey:"shortcutKey"); preferences.set(Int(shortcutModifiers),forKey:"shortcutModifiers"); preferences.set(chosenPreset,forKey:"chosenPreset")
        preferences.set(audioSensitivity,forKey:"audioSensitivity"); preferences.set(motionFPS,forKey:"motionFPS")
        if quota?.isDemo != true && quotaBucket != "demo" { preferences.set(quotaBucket,forKey:"quotaBucket") }
        if let data = try? JSONEncoder().encode(quotaDisplay) { preferences.set(data,forKey:"quotaDisplay") }
        preferences.set(2,forKey:"agentLayoutVersion")
    }
    private func rememberAppliedLight() {
        guard !CommandLine.arguments.contains("--render-preview") else { return }
        if let data = try? JSONEncoder().encode(appliedSettings) { preferences.set(data, forKey:"lastAppliedLight") }
        preferences.set(activeBasePattern.rawValue,forKey:"lastAppliedPattern")
        preferences.set(baseReports?.count == 1,forKey:"lastAppliedFirmware")
    }
    private func restoreSavedDeviceSettings() {
        guard let data = preferences.data(forKey:"lastAppliedLight"), data.count < 4096,
              let light = try? JSONDecoder().decode(LightSettings.self,from:data), (try? RKCodec.lighting(light)) != nil else { return }
        let pattern = BasicPattern(rawValue: preferences.string(forKey:"lastAppliedPattern") ?? "") ?? .solid
        perform {
            let base = LightingComposer.base(layout:layout,settings:light,pattern:pattern)
            let savedAgent = preferences.integer(forKey:"agentConfigAppliedVersion") == 1 && !activeAgent.keys.isEmpty
            let useFirmware = preferences.bool(forKey:"lastAppliedFirmware") && !preferredAgentPinned && !savedAgent && !light.rainbow && (pattern == .breathing || pattern == .marquee)
            firmwareMode = useFirmware
            let reports = useFirmware ? [try RKCodec.lighting(light)] : try RKCodec.customLighting(layout:layout,colors:base,sleep:light.sleep)
            try hid.send(reports)
            baseColors = base; baseReports = reports; activeBasePattern = pattern; appliedColors = base; appliedSettings = light; appliedReports = reports; appliedLight = true
            dynamicNotificationsEnabled = preferredDynamicNotifications
            record("已恢复上次成功应用的灯光")
        }
        guard connected, appliedLight else { return }
        restorePreferredQuotaSettings()
        if directStreamEnabled && activeBasePattern.motion != nil && (!firmwareMode || hasAppliedAgent) { startLiveEngine(kind:"base") }
        if musicRequested && directStreamEnabled {
            if audioPlaying { musicLightingEnabled = true; startLiveEngine(kind:"music") }
            else { startSystemAudio() }
        }
        if preferredNotifications {
            if !directStreamEnabled { systemNotificationStatus = "通知设置已保存，请确认新的实时通道。" }
            else if SystemBannerMonitor.hasPermission { startBannerMonitor() }
            else { systemNotificationStatus = "已保留通知设置，等待辅助功能授权" }
        }
    }
    private func restorePreferredQuotaSettings() {
        guard preferences.integer(forKey:"agentConfigAppliedVersion") == 1, restoreOnConnect, connected, canSyncQuota, !agentRestoredThisSession else { return }
        agentPinned = preferredAgentPinned; quotaHardwareAuto = preferredHardwareAuto
        if !sendQuotaFrame(automatic:false) { agentPinned = false; quotaHardwareAuto = false }
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription; record("失败：\(error.localizedDescription)") }
        connected = hid.connected
        if !connected && (appliedLight || notificationActive) { invalidateDeviceSession() }
    }
    func scan() {
        let devices = hid.scan()
        detected = devices.contains { ($0[kIOHIDVendorIDKey] as? Int) == 0x258a && ($0[kIOHIDProductIDKey] as? Int) == 0x00c1 }
        receiverDetected = devices.contains { ($0[kIOHIDVendorIDKey] as? Int) == 0x25a7 && ($0[kIOHIDProductIDKey] as? Int) == 0xfa70 }
        status = connected ? "控制接口已连接" : (detected ? "RK98 已识别 · 等待连接" : (receiverDetected ? ReceiverResearch.unavailable : "没有检测到目标键盘"))
    }
    var receiverOnly:Bool { receiverDetected && !detected && !connected }
    func connect() {
        guard resourcesReady else { error = startupError; return }
        invalidateDeviceSession()
        perform { try hid.open(); connected = true; status = "USB 控制接口已连接"; record("成功打开 USB 控制接口") }
        if connected {
            preferences.set(true, forKey: "wasConnected")
            if restoreOnConnect && riskAccepted { restoreSavedDeviceSettings() }
        }
    }
    func permissions() {
        // macOS exposes this composite control interface as a protected keyboard.
        // We do not register any input callbacks or capture typed content.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    func save() {
        guard resourcesReady else { return }
        if profile.workflow != workflow { profile.workflow = workflow }
        guard (try? profile.validate(layout: layout, codes: codes)) != nil else { error = "配置无效，未保存。"; return }
        if let data = try? JSONEncoder().encode(profile) { preferences.set(data, forKey: "labProfile") }
    }
    private var liveProtocolNotice: String {
        directStreamEnabled ? "" : "实时颜色通道参考 RK61/RK84，尚未在本机 RK98 验证。首次启用属于实验适配；如果仍闪烁或无响应请立即停用。"
    }
    private func authorizeLiveProtocol() {
        directStreamEnabled = true; preferences.set(1,forKey:"liveProtocolConsent")
    }
    private func cancelPendingLiveFrame() {
        guard lightingActive else { return }
        liveGeneration += 1; liveInFlight = false; lastMotionWrite = nil; lastMotionSubmitted = nil
        hid.endColorStream(); hid.beginColorStream()
    }
    func applyLight() {
        let native = basicPattern == .breathing || basicPattern == .marquee
        let needsLive = basicPattern.motion != nil && (!native || profile.light.rainbow || agentPinned || preferredAgentPinned || hasAppliedAgent)
        requestWrite("应用当前基础灯效、颜色和亮度。" + (needsLive ? liveProtocolNotice : "") + "固定额度键保持优先。") { [weak self] in
            guard let self else { return }
            if needsLive { self.authorizeLiveProtocol() }
            self.firmwareMode = native && !needsLive
            if self.firmwareMode { self.profile.light.mode = self.basicPattern == .breathing ? 18 : 9 }
            self.applyLightConfirmed()
        }
    }
    private func applyLightConfirmed() {
        perform {
            try profile.validate(layout: layout, codes: codes)
            stopLighting(restore: false)
            cancelNotification(restore: false)
            if !agentPinned && !preferredHardwareAuto { quotaHardwareAuto = false }
            let base = LightingComposer.base(layout: layout, settings: profile.light, pattern: basicPattern)
            let idle = composeIdle(base: base)
            let reports = usesComposedLighting ? try RKCodec.customLighting(layout: layout, colors: idle, sleep: agentPinned ? 5 : profile.light.sleep) : [try RKCodec.lighting(profile.light)]
            try hid.send(reports)
            baseColors = base; activeBasePattern = basicPattern
            baseReports = firmwareMode ? [try RKCodec.lighting(profile.light)] : try RKCodec.customLighting(layout:layout,colors:base,sleep:profile.light.sleep)
            appliedReports = reports; appliedColors = usesComposedLighting ? idle : base
            appliedSettings = profile.light; appliedLight = true
            rememberAppliedLight()
            save(); record("基础灯效已应用")
        }
        if connected && appliedLight && directStreamEnabled {
            if musicLightingEnabled { startLiveEngine(kind:"music") }
            else if !firmwareMode && activeBasePattern.motion != nil { startLiveEngine(kind:"base") }
        }
    }
    func notify() {
        perform {
            guard resourcesReady, connected, appliedLight, appliedReports != nil else { throw RKError.message("请先连接并应用基础灯光。") }
            let now = lightingClock()
            if let last = lastNotificationAt, now-last < 10 { throw RKError.message("通知间隔至少 10 秒。") }
            try notificationSettings.validate(layout)
            guard !effectiveNotificationKeys.isEmpty else { throw RKError.message("通知键均与固定额度重叠，请重新选键。") }
            guard directStreamEnabled else { throw RKError.message("请先启用实时通知通道。") }
            guard notificationSettings.pattern.motion == nil || dynamicNotificationsEnabled else { throw RKError.message("请先开启实验动态通知。") }
            cancelNotification(restore:false)
            let session = connectionGeneration, notification = notificationGeneration
            let notice = notificationSettings.colors(layout:layout,background:[:],time:0,pulse:true)
            let background = lightingActive ? motionBase(at:now) : (appliedColors ?? emptyFrame)
            let frame = LightingComposer.frame(base:background,agent:pinnedAgentColors,reservedAgentKeys:agentPinned ? pinnedAgentKeys : [],notificationKeys:effectiveNotificationKeys,notice:notice)
            if !lightingActive { hid.beginColorStream() } else { cancelPendingLiveFrame() }
            try hid.send(RKCodec.liveColors(layout:layout,colors:frame))
            lastNotificationAt = now; notificationStarted = now
            notificationActive = true; activeNoticeColors = notice; motionNotice = notificationSettings
            if !lightingActive { startLiveEngine(kind:"notice") }
            record("通知显示 5 秒，静态图案自动呼吸")
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.connectionGeneration == session, self.notificationGeneration == notification, self.connected, self.appliedLight else { return }
                self.notificationActive = false; self.activeNoticeColors = nil
                if self.lightingActive && self.motionKind == "notice" { self.stopLighting(restore:false) }
                if self.lightingActive {
                    self.lastMotionFrame = nil; self.lastMotionWrite = nil; self.tickLighting()
                } else {
                    self.perform { if let reports = self.appliedReports { try self.hid.send(reports) } }
                }
                self.record("通知结束，选区重新跟随整体灯光")
            }
            notificationReturn = work
            DispatchQueue.main.asyncAfter(deadline:.now()+5,execute:work)
        }
    }
    func cancelNotification(restore: Bool) {
        notificationGeneration += 1; notificationReturn?.cancel(); notificationReturn = nil
        let wasActive = notificationActive
        notificationActive = false; activeNoticeColors = nil
        if lightingActive && motionKind == "notice" { stopLighting(restore:false) }
        if restore && wasActive, let reports = appliedReports { perform { try hid.send(reports) } }
    }
    private func invalidateDeviceSession() {
        connectionGeneration += 1
        stopLighting(restore: false); musicLightingEnabled = false; dynamicNotificationsEnabled = false; motionFramesWritten = 0
        agentRestoredThisSession = false
        cancelNotification(restore: false); stopFocus(); cancelWrite()
        appliedLight = false; lastPhysicalSync = nil; appliedReports = nil; appliedColors = nil
        quotaHardwareAuto = false; agentPinned = false; pinnedAgentKeys = []; pinnedAgentColors = [:]; baseColors = nil; baseReports = nil
        stopSystemNotifications(); lastQuotaFrame = nil; lastQuotaWrite = nil
    }
    func startFocus() {
        guard resourcesReady, connected, appliedLight else { error = "请先连接键盘并应用本次连接的基础灯效，再启动专注计时。"; return }
        guard (1...120).contains(focusMinutes) else { error = "专注时间应为 1–120 分钟。"; return }
        stopFocus()
        remaining = focusMinutes * 60
        focusDeadline = Date().addingTimeInterval(Double(remaining))
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let deadline = self.focusDeadline else { return }
            self.remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            if self.remaining == 0 {
                self.stopFocus(); NSSound(named: "Glass")?.play(); self.notify(); self.record("专注计时结束")
            }
        }
        record("开始 \(focusMinutes) 分钟专注计时")
    }
    func stopFocus() { focusTimer?.invalidate(); focusTimer = nil; focusDeadline = nil; remaining = 0 }

    func stageMapping() {
        guard let index = selectedKey else { return }
        profile.overrides[index] = targetCode; save()
    }
    func applyMapping() {
        requestWrite("发送完整 100 键默认布局及你的修改，共 9 个报告。会覆盖已有自定义映射，无法恢复未知的原配置。") { [weak self] in self?.applyMappingConfirmed() }
    }
    private func applyMappingConfirmed() {
        perform {
            try profile.validate(layout: layout, codes: codes)
            try hid.send(RKCodec.keymap(layout: layout, codes: codes, overrides: profile.overrides))
            save(); record("9 个按键映射报告已发送；请测试实物按键。未修改的键使用公开默认布局。")
        }
    }
    func resetMapping() {
        guard resourcesReady, requireResearchConsent() else { return }
        perform {
            try hid.send(RKCodec.keymap(layout: layout, codes: codes, overrides: [:]))
            profile.overrides = [:]; save(); record("已发送公开默认按键布局")
        }
    }
    func exportProfile() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "rk98-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(profile).write(to: url, options: .atomic); record("配置已导出") }
    }
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let p = try LabProfile.read(from: url, layout: layout, codes: codes)
            profile = p; workflow = p.workflow ?? "灯光通知"; save(); record("配置已导入界面，尚未发送到键盘")
        }
    }
    func startSystemAudio() {
        guard musicRequested, !audioPlaying, !audioStarting, !CommandLine.arguments.contains("--render-preview") else { return }
        audioGeneration += 1; let generation = audioGeneration
        audioStarting = true; audioError = nil; audioTitle = "正在连接系统声音…"
        let capture = SystemAudioCapture(onFrame: { [weak self] level,bands in
            guard let self, self.audioGeneration == generation else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let interval = self.lastAudioSample > 0 ? now-self.lastAudioSample : 1.0/Double(LightingRate.maximumFPS)
            self.lastAudioSample = now; self.audioLevel = level
            self.updateAudioBands(bands,interval:interval)
            self.audioTitle = level > 0.01 ? "正在跟随系统播放" : "已连接 · 等待系统播放声音"
        }, onFailure: { [weak self] in
            guard let self, self.audioGeneration == generation else { return }
            self.stopMusic(); self.audioError = "系统音频采集中断，请检查授权或音频设备后重新连接。"
        })
        systemAudio = capture
        Task { @MainActor [weak self] in
            do {
                try await capture.start()
                guard let self, self.audioGeneration == generation else { capture.stop(); return }
                self.audioStarting = false; self.audioPlaying = true; self.audioTitle = "已连接 · 等待系统播放声音"
                if self.musicRequested && self.directStreamEnabled && self.connected && self.appliedLight { self.musicLightingEnabled = true; self.startLiveEngine(kind:"music") }
                self.startAudioDecay(generation: generation)
                self.record("已连接系统播放音频；只计算音量，不录制或保存音频")
            } catch {
                guard let self, self.audioGeneration == generation else { return }
                self.stopMusic()
                self.audioTitle = "系统声音尚未连接"
                self.audioError = "无法采集系统声音。请在系统设置的「屏幕与系统音频录制」中允许 FeralKey，必要时退出后重开，再点重试。也请检查可用显示器和音频设备。"
            }
        }
    }
    private func startAudioDecay(generation: Int) {
        audioDecayTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.audioGeneration == generation else { return }
            if ProcessInfo.processInfo.systemUptime-self.lastAudioSample > 0.3 {
                self.audioLevel = self.audioLevel < 0.01 ? 0 : self.audioLevel*0.6
                self.updateAudioBands([],interval:0.1)
                self.audioTitle = "已连接 · 等待系统播放声音"
            }
        }
        audioDecayTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stopMusic(resumeBase:Bool = true) {
        if musicLightingEnabled { musicLightingEnabled = false; stopLighting(restore:true) }
        audioGeneration += 1; audioDecayTimer?.invalidate(); audioDecayTimer = nil; systemAudio?.stop(); systemAudio = nil
        musicRequested = false; audioStarting = false; audioPlaying = false; audioLevel = 0
        audioBands = [Double](repeating:0,count:AudioSpectrumAnalyzer.bandCount)
        audioReactor = AudioSpectrumReactor(); lastAudioSample = 0; audioTitle = "未启用 · 等待手动开启"
        if resumeBase && connected && directStreamEnabled && activeBasePattern.motion != nil && (!firmwareMode || hasAppliedAgent) { startLiveEngine(kind:"base") }
    }
    private func updateAudioBands(_ bands:[Double],interval:Double) {
        audioBands = audioReactor.update(bands,sensitivity:audioSensitivity,interval:interval)
    }
    func audioPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func toggleHotkey() {
        if hotkeysEnabled { preferredHotkeys = false; disableHotkey(); return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context = context else { return OSStatus(eventNotHandledErr) }
            let model = Unmanaged<LabModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { model.runWorkflow() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { error = "快捷键处理器注册失败（\(result)）"; return }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_1), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x524b3938, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        guard status == noErr else { disableHotkey(); error = "快捷键被占用（\(status)），请关闭冲突应用后重试"; return }
        hotkeysEnabled = true; preferredHotkeys = true; save(); record("启用 Mac 全局快捷键 ⌃⌥⌘1；适用于所有键盘")
    }
    func disableHotkey() {
        if let key = hotkey { UnregisterEventHotKey(key) }; hotkey = nil
        if let h = handler { RemoveEventHandler(h) }; handler = nil
        hotkeysEnabled = false
    }
    func setHotkeyEnabled(_ enabled:Bool) {
        if !enabled { preferredHotkeys = false; disableHotkey() }
        else if !hotkeysEnabled { toggleHotkey() }
    }
    func runWorkflow() {
        switch workflow {
        case "专注计时": startFocus()
        case "打开网址":
            guard let url = URL(string: profile.shortcutURL), ["https","http"].contains(url.scheme?.lowercased() ?? "") else { error = "请输入 http 或 https 网址"; return }
            NSWorkspace.shared.open(url); save()
        case "运行快捷指令":
            guard !profile.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请先填写 macOS 快捷指令名称"; return }
            var url = URLComponents(); url.scheme = "shortcuts"; url.host = "run-shortcut"; url.queryItems = [URLQueryItem(name: "name", value: profile.shortcutName)]
            if let link = url.url { NSWorkspace.shared.open(link); save() }
        default: notify()
        }
    }
    func handleURL(_ url: URL) {
        guard ["rk98lab", "feralkey"].contains(url.scheme ?? "") else { return }
        switch url.host {
        case "notify":
            requestWrite("外部链接请求一次灯光通知：发送选定键区的图案，5 秒后恢复本次连接之前的灯光。") { [weak self] in self?.notify() }
        case "focus":
            guard connected && appliedLight else { error = "请先连接键盘并应用基础灯效，再启动专注计时"; return }
            requestWrite("外部链接请求启动 \(focusMinutes) 分钟专注计时；到期后会发送选定键区的通知图案，5 秒后恢复本次连接的基础灯效。重连会取消计时。") { [weak self] in self?.startFocus() }
        default: error = "未知操作，只支持 feralkey://notify 和 feralkey://focus"
        }
    }
    func cleanup() {
        persistUserSettings()
        stopLighting(restore: true)
        quotaGeneration += 1; quotaCancellation.cancel(); quotaTimer?.invalidate(); quotaClock?.invalidate()
        stopSystemNotifications(); cancelNotification(restore: true); stopFocus(); stopMusic(resumeBase:false); disableHotkey(); hid.close(); save()
    }

    func navigate(_ title: String) {
        page = title
        if title == "探索向导" {
            if requireResearchConsent() { discovered = DeviceDiscovery.scan() }
        }
    }
    @discardableResult func requireResearchConsent() -> Bool {
        if riskAccepted { return true }
        riskChecked = false; riskSheet = true
        return false
    }
    func acceptResearchRisk() {
        guard riskChecked else { return }
        riskAccepted = true; hid.writesAuthorized = true; riskSheet = false
        preferences.set(ResearchNotice.version, forKey: "researchConsentVersion")
        discovered = DeviceDiscovery.scan()
        record("已接受第 \(ResearchNotice.version) 版实验风险须知；没有发送设备报告")
    }
    func requestWrite(_ text: String, action: @escaping () -> Void) {
        guard resourcesReady else { error = startupError; return }
        guard writePrompt == nil else { return }
        guard requireResearchConsent() else { return }
        pendingWrite = action; writePrompt = text
    }
    func approveWrite() {
        let action = pendingWrite; pendingWrite = nil; writePrompt = nil
        guard riskAccepted else { return }; action?()
    }
    func cancelWrite() { pendingWrite = nil; writePrompt = nil }
    func refreshDiscovery() { guard requireResearchConsent() else { return }; discovered = DeviceDiscovery.scan(); scan() }
    func exportResearch() {
        guard requireResearchConsent() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "feralkey-device-research.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try DeviceDiscovery.researchPackage(devices: discovered).write(to: url, options: .atomic); record("研究包已导出；请检查产品名称后再公开分享") }
    }

    func activate() {
        guard !activated, !CommandLine.arguments.contains("--render-preview"), resourcesReady else { return }
        activated = true
        quotaClock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.quotaNow = Date() }
        RunLoop.main.add(quotaClock!, forMode: .common)
        if autoConnect && preferences.bool(forKey: "wasConnected") && riskAccepted && !receiverOnly {
            if inputPermissionGranted { connect() }
            else { status = "等待输入监控授权 · 设置已保留" }
        }
        if preferredHotkeys && !hotkeysEnabled { toggleHotkey() }
        if preferences.object(forKey: "quotaAutoRefresh") as? Bool ?? true { startQuota() }
        else { refreshQuota() }
    }
    func setQuotaInterval(_ interval: Int) {
        guard RefreshSchedule.intervals.contains(interval) else { return }
        quotaInterval = interval; preferences.set(interval, forKey: "quotaInterval")
        if quotaAutoRefresh { scheduleQuotaTimer() }
    }
    private func scheduleQuotaTimer() {
        quotaTimer?.invalidate()
        nextQuotaRefresh = Date().addingTimeInterval(Double(quotaInterval))
        let timer = Timer(timeInterval: Double(quotaInterval), repeats: true) { [weak self] _ in
            guard let self else { return }
            self.nextQuotaRefresh = Date().addingTimeInterval(Double(self.quotaInterval))
            self.refreshQuota()
        }
        quotaTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func startQuota() {
        guard !CommandLine.arguments.contains("--render-preview") else { return }
        quotaAutoRefresh = true; preferences.set(true, forKey: "quotaAutoRefresh")
        scheduleQuotaTimer(); refreshQuota()
    }
    func stopQuota(persist: Bool = true) {
        quotaAutoRefresh = false; quotaHardwareAuto = false; nextQuotaRefresh = nil
        if persist && !CommandLine.arguments.contains("--render-preview") { preferences.set(false, forKey: "quotaAutoRefresh") }
        quotaTimer?.invalidate(); quotaTimer = nil
        quotaCancellation.cancel(); quotaGeneration += 1; quotaLoading = false
    }
    func refreshQuota() {
        guard !quotaLoading else { return }
        guard let executable = CodexClient.locate(override: codexPath) else {
            quotaError = "没有找到 Codex。安装并使用 ChatGPT 登录 Codex CLI，或在下方选择已有可执行文件。"; return
        }
        quotaLoading = true
        quotaGeneration += 1; let generation = quotaGeneration
        quotaCancellation = CodexReadCancellation(); let cancellation = quotaCancellation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try CodexClient.fetch(executable: executable, cancellation: cancellation) }
            DispatchQueue.main.async {
                guard let self, self.quotaGeneration == generation else { return }
                self.quotaLoading = false; self.quotaNow = Date()
                switch result {
                case .success(let snapshot):
                    self.quota = snapshot; self.quotaError = nil
                    if snapshot.buckets[self.quotaBucket] == nil {
                        self.quotaBucket = snapshot.buckets["codex"] != nil ? "codex" : (snapshot.buckets.count == 1 ? snapshot.buckets.keys.first! : "")
                    }
                    self.restorePreferredQuotaSettings()
                    self.syncQuotaAutomaticallyIfNeeded()
                case .failure(let error): self.quotaError = error.localizedDescription
                }
            }
        }
    }
    func demoQuota() {
        stopQuota(persist: false); quotaGeneration += 1; quotaLoading = false
        quota = .demo(); quotaBucket = "demo"; quotaError = nil; quotaNow = Date()
    }
    func chooseCodex() {
        let panel = NSOpenPanel(); panel.message = "选择你已安装的 Codex 可执行文件（不是 .app 文件夹）"; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard CodexClient.isExecutableFile(url.path) else { error = "请选择普通可执行文件。"; return }
        stopQuota(); codexPath = url.path; preferences.set(codexPath, forKey: "codexPath"); startQuota()
    }
    func quotaRemaining(_ minutes: Int, at: Date? = nil) -> Double? {
        quota?.remaining(bucket: quotaBucket, minutes: minutes, at: at ?? quotaNow, failed: quotaError != nil, maximumAge: RefreshSchedule.maximumAge(quotaInterval))
    }
    var draftAgent: AgentConfiguration { AgentConfiguration(zones:quotaZones,palette:agentPalette,display:quotaDisplay) }
    var agentNeedsApply: Bool { draftAgent != activeAgent || preferences.integer(forKey:"agentConfigAppliedVersion") != 1 }
    var quotaColors: [Int: RGB] { draftAgent.colors(fiveHour:quotaRemaining(300),weekly:quotaRemaining(10080)) }
    func selectKey(_ key: PhysicalKey) {
        if page == "灯效与通知" && lightingTab == 1 && notificationEditing {
            if agentPinned && pinnedAgentKeys.contains(key.id) { error = "此键已固定为 Agent 额度灯，请先修改额度区域或取消固定。"; return }
            if notificationSettings.keys.contains(key.id) { notificationSettings.keys.removeAll { $0 == key.id } }
            else { notificationSettings.keys.append(key.id) }
            saveNotification(); return
        }
        guard page == "Agent额度灯", quotaEditing != 0 else { selectedKey = key.id; return }
        guard (0..<10).contains(quotaSlot) else { return }
        var first = quotaZones.fiveHour, second = quotaZones.weekly
        let old = quotaEditing == 1 ? first[quotaSlot] : second[quotaSlot]
        if let index = first.firstIndex(of:key.id) { first[index] = old }
        if let index = second.firstIndex(of:key.id) { second[index] = old }
        if quotaEditing == 1 { first[quotaSlot] = key.id } else { second[quotaSlot] = key.id }
        quotaZones = QuotaZones(fiveHour:first,weekly:second)
        quotaSlot = (quotaSlot+1)%10
    }
    func quotaMarker(_ key:Int) -> String? {
        if (quotaDisplay.fiveHourEnabled || quotaEditing == 1), let index = quotaZones.fiveHour.firstIndex(of:key) { return "\((index+1)*10)%" }
        if (quotaDisplay.weeklyEnabled || quotaEditing == 2), let index = quotaZones.weekly.firstIndex(of:key) { return "\((index+1)*10)%" }
        return nil
    }
    func keySelectedInPreview(_ key:Int) -> Bool {
        if page == "Agent额度灯" {
            let ids = quotaEditing == 2 ? quotaZones.weekly : quotaZones.fiveHour
            return ids.indices.contains(quotaSlot) && ids[quotaSlot] == key
        }
        if page == "灯效与通知" && lightingTab == 1 && notificationEditing { return notificationSettings.keys.contains(key) }
        return page == "按键工作流" && selectedKey == key
    }

    func resetQuotaZones() {
        quotaZones = .defaults(layout: layout)
        if let data = try? JSONEncoder().encode(quotaZones) { preferences.set(data, forKey: "quotaZones") }
    }
    private func canUseAgent(_ config:AgentConfiguration) -> Bool {
        guard resourcesReady, connected, (try? config.zones.validate(layout:layout)) != nil else { return false }
        if config.keys.isEmpty { return true }
        return quota?.isDemo == false && (!config.display.fiveHourEnabled || quotaRemaining(300,at:Date()) != nil) && (!config.display.weeklyEnabled || quotaRemaining(10080,at:Date()) != nil)
    }
    var canSyncQuota: Bool { !activeAgent.keys.isEmpty && canUseAgent(activeAgent) }
    var canApplyAgent: Bool { canUseAgent(draftAgent) }
    func syncQuota() { applyAgentConfiguration() }
    func applyAgentConfiguration() {
        let needsLive = !draftAgent.keys.isEmpty && activeBasePattern.motion != nil
        requestWrite("应用已选额度灯：每组 10 个键，对应 10% 至 100%。关闭的灯条回归基础灯光；首次尚无底色时使用当前软件底色。" + (needsLive ? liveProtocolNotice : "")) { [weak self] in
            guard let self else { return }
            if needsLive { self.authorizeLiveProtocol() }
            let candidate = self.draftAgent
            if self.sendQuotaFrame(automatic:false,configuration:candidate) {
                self.agentConfigurationStatus = "已应用"
                if needsLive && !self.musicLightingEnabled { self.startLiveEngine(kind:"base") }
            }
        }
    }
    func applyAgentFromEditor() {
        quotaLayoutExpanded = false
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { [weak self] in self?.applyAgentConfiguration() }
    }
    func setQuotaHardwareAuto(_ enabled: Bool) {
        if !enabled { preferredHardwareAuto = false; quotaHardwareAuto = false; return }
        guard canSyncQuota else { error = "请先连接键盘并读取有效的真实额度。"; return }
        requestWrite("启用本次连接的自动灯条：每次成功读取额度后按所选间隔同步，仅颜色变化才写入。当前协议可能保存到内部存储。偏好自动保存，重新连接后等待真实额度恢复；开启固定后，基础灯效会保留额度区。") { [weak self] in
            guard let self, self.canSyncQuota else { return }
            self.quotaHardwareAuto = true; self.preferredHardwareAuto = true
            if !self.quotaAutoRefresh { self.startQuota() }
            self.sendQuotaFrame(automatic: false)
        }
    }
    func syncQuotaAutomaticallyIfNeeded() {
        restorePreferredQuotaSettings()
        guard quotaHardwareAuto, quotaAutoRefresh, canSyncQuota, (!notificationActive || agentPinned), writePrompt == nil else { return }
        sendQuotaFrame(automatic: true)
    }
    @discardableResult private func sendQuotaFrame(automatic: Bool, configuration:AgentConfiguration? = nil) -> Bool {
        var successful = false
        perform {
            let config = configuration ?? activeAgent
            guard canUseAgent(config) else { throw RKError.message("请连接键盘，并读取启用灯条所需的真实额度。") }
            try config.zones.validate(layout:layout)
            let colors = config.colors(fiveHour:quotaRemaining(300,at:Date()),weekly:quotaRemaining(10080,at:Date()))
            let now = quotaWriteClock()
            if automatic {
                if colors == lastQuotaFrame { return }
                if let lastQuotaWrite, now-lastQuotaWrite < Double(quotaInterval) { return }
            }
            let keys = config.keys
            let base = baseColors ?? LightingComposer.base(layout:layout,settings:profile.light,pattern:.solid)
            let idle = LightingComposer.frame(base: base, agent: colors, reservedAgentKeys: keys, notificationKeys: [], notice: nil)
            let visible = notificationActive ? LightingComposer.frame(base: idle, agent: colors, reservedAgentKeys: agentPinned ? keys : [], notificationKeys: effectiveNotificationKeys, notice: activeNoticeColors) : idle
            let reports = config.keys.isEmpty && baseReports != nil ? baseReports! : try RKCodec.customLighting(layout: layout, colors: visible, sleep: agentPinned ? 5 : appliedSettings.sleep)
            let idleReports = config.keys.isEmpty && baseReports != nil ? baseReports! : try RKCodec.customLighting(layout: layout, colors: idle, sleep: agentPinned ? 5 : appliedSettings.sleep)
            if lightingActive {
                cancelPendingLiveFrame()
                try hid.send(RKCodec.liveColors(layout:layout,colors:visible))
            } else { try hid.send(reports) }
            if baseColors == nil {
                baseColors = base; activeBasePattern = .solid; appliedSettings = profile.light
                baseReports = try RKCodec.customLighting(layout:layout,colors:base,sleep:profile.light.sleep)
                rememberAppliedLight()
            }
            activeAgent = config
            agentRestoredThisSession = true
            if !automatic { preferences.set(1,forKey:"agentConfigAppliedVersion") }
            if config.keys.isEmpty {
                agentPinned = false; preferredAgentPinned = false; quotaHardwareAuto = false; preferredHardwareAuto = false
                pinnedAgentKeys = []; pinnedAgentColors = [:]
            }
            if let data = try? JSONEncoder().encode(config) { preferences.set(data,forKey:"appliedAgentConfiguration") }
            if agentPinned { pinnedAgentKeys = keys; pinnedAgentColors = colors }
            appliedLight = true; appliedReports = idleReports; appliedColors = idle
            lastQuotaFrame = colors; lastQuotaWrite = now; lastPhysicalSync = Date()
            record(automatic ? "已自动同步变化后的额度灯条" : "已同步一次额度灯条；请观察实物")
            successful = true
        }
        return successful
    }
    func saveNotification() {
        if let data = try? JSONEncoder().encode(notificationSettings) { preferences.set(data, forKey: "notificationSettings") }
    }
    func resetNotificationKeys() { notificationSettings = .defaults(layout); saveNotification() }
    var notificationColors: [Int: RGB] {
        let base = LightingComposer.base(layout: layout, settings: profile.light, pattern: basicPattern)
        return LightingComposer.frame(base: base, agent: pinnedAgentColors, reservedAgentKeys: agentPinned ? pinnedAgentKeys : [], notificationKeys: effectiveNotificationKeys, notice: notificationSettings.colors(layout: layout, background: [:]))
    }
    var emptyFrame: [Int: RGB] { Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.id, QuotaRenderer.off) }) }
    var usesComposedLighting: Bool { !firmwareMode || agentPinned || hasAppliedAgent }
    var effectiveNotificationKeys: Set<Int> { Set(notificationSettings.keys).subtracting(agentPinned ? pinnedAgentKeys : []) }
    var notificationOverlapCount: Int { notificationSettings.keys.count - effectiveNotificationKeys.count }
    private var hasAppliedAgent: Bool { lastPhysicalSync != nil && !activeAgent.keys.isEmpty }
    func composeIdle(base: [Int: RGB]) -> [Int: RGB] {
        LightingComposer.frame(base:base,agent:lastQuotaFrame ?? [:],reservedAgentKeys:hasAppliedAgent ? activeAgent.keys : [],notificationKeys:[],notice:nil)
    }
    func saveAgentPalette() {
        if let data = try? JSONEncoder().encode(agentPalette) { preferences.set(data, forKey: "agentPalette") }
    }
    func setAgentPinned(_ enabled: Bool) {
        if !enabled { preferredAgentPinned = false; agentPinned = false; pinnedAgentKeys = []; pinnedAgentColors = [:]; return }
        guard canSyncQuota else { error = "请先连接键盘并读取有效的真实额度。"; return }
        requestWrite("固定本次连接的 Agent 额度区并自动更新，基础灯光和通知不能覆盖这些键。整板原生动画将使用区域静态底色；通知重叠键保留给额度。配置可能保存到键盘内部存储。") { [weak self] in
            guard let self, self.canSyncQuota else { return }
            self.agentPinned = true; self.quotaHardwareAuto = true; self.preferredAgentPinned = true; self.preferredHardwareAuto = true
            if !self.quotaAutoRefresh { self.startQuota() }
            if !self.sendQuotaFrame(automatic: false) {
                self.agentPinned = false; self.quotaHardwareAuto = false; self.pinnedAgentKeys = []; self.pinnedAgentColors = [:]
            }
        }
    }
    func saveLightingRegions() {
        preferences.set(separateNotificationRegion, forKey: "separateNotificationRegion")
        preferences.set(basicPattern.rawValue, forKey: "basicPattern")
    }
    func setBasePattern(_ pattern: BasicPattern) {
        basicPattern = pattern
        // All visible controls preserve applied Agent regions.
        firmwareMode = false
        saveLightingRegions()
    }
    func setBaseColor(_ color: RGB) { profile.light.color = color; profile.light.rainbow = false }
    func applyRegionSettings() {
        saveNotification(); record("通知设置已保存；没有改动基础灯光")
    }
    func testNotification() {
        requestWrite("显示通知 5 秒，结束回归整体灯光。" + liveProtocolNotice) { [weak self] in
            guard let self else { return }
            self.authorizeLiveProtocol()
            if self.notificationSettings.pattern.motion != nil { self.dynamicNotificationsEnabled = true; self.preferredDynamicNotifications = true }
            if self.preferredNotifications && SystemBannerMonitor.hasPermission { self.startBannerMonitor() }
            self.notify()
        }
    }
    func setDynamicNotifications(_ enabled:Bool) {
        if !enabled { preferredDynamicNotifications = false; dynamicNotificationsEnabled = false; cancelNotification(restore:true); return }
        requestWrite("启用实时通知灯光。" + liveProtocolNotice) { [weak self] in
            guard let self else { return }; self.authorizeLiveProtocol(); self.dynamicNotificationsEnabled = true; self.preferredDynamicNotifications = true
        }
    }
    func setMusicLighting(_ enabled:Bool) {
        if !enabled {
            musicRequested = false; musicLightingEnabled = false
            stopLighting(restore:true); stopMusic(resumeBase:false)
            if connected && (!firmwareMode || hasAppliedAgent) && activeBasePattern.motion != nil && directStreamEnabled { startLiveEngine(kind:"base") }
            return
        }
        guard connected else { connectionSheet = true; return }
        requestWrite("启用系统音频灯光，持续运行直至停用；首次没有基础灯光时会应用当前静态底色。" + liveProtocolNotice) { [weak self] in
            guard let self else { return }
            self.authorizeLiveProtocol()
            if !self.appliedLight { self.firmwareMode = false; self.applyLightConfirmed() }
            guard self.connected, self.appliedLight else { return }
            self.musicRequested = true
            if self.audioPlaying { self.musicLightingEnabled = true; self.startLiveEngine(kind:"music") }
            else { self.startSystemAudio() }
        }
    }
    private func startLiveEngine(kind:String) {
        guard directStreamEnabled, connected, appliedLight, LightingRate.choices.contains(motionFPS) else { return }
        stopLighting(restore:false)
        motionKind = kind
        motionNotice = notificationSettings
        motionStarted = lightingClock(); activeMotionFPS = motionFPS
        lightingActive = true; lastMotionFrame = nil; lastMotionWrite = nil; lastMotionSubmitted = nil
        hid.beginColorStream(); motionStatus = "实时灯光已启用 · 目标 \(motionFPS) FPS"
        scheduleLightingTimer()
    }
    func setMotionFPS(_ fps:Int) {
        guard LightingRate.choices.contains(fps) else { return }
        motionFPS = fps
        if lightingActive { scheduleLightingTimer() }
    }
    private func scheduleLightingTimer() {
        motionTimer?.invalidate(); activeMotionFPS = motionFPS
        motionStatus = "实时灯光已启用 · 目标 \(motionFPS) FPS"
        let timer = Timer(timeInterval:1/Double(activeMotionFPS),repeats:true) { [weak self] _ in self?.tickLighting() }
        motionTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func motionBase(at now:TimeInterval) -> [Int:RGB] {
        if musicLightingEnabled { return MotionRenderer.audioFrame(layout:layout,bands:audioBands,color:appliedSettings.color,rainbow:appliedSettings.rainbow,brightness:Double(appliedSettings.brightness)/5) }
        let base = activeBasePattern.motion != nil ? LightingComposer.base(layout:layout,settings:appliedSettings,pattern:activeBasePattern,time:now-motionStarted) : (appliedColors ?? emptyFrame)
        return LightingComposer.frame(base:base,agent:lastQuotaFrame ?? [:],reservedAgentKeys:hasAppliedAgent ? activeAgent.keys : [],notificationKeys:[],notice:nil)
    }
    func tickLighting() {
        guard lightingActive, !liveInFlight else { return }
        let now = lightingClock()
        guard connected else { stopLighting(restore:false); return }
        if let lastMotionSubmitted, now-lastMotionSubmitted < 1/Double(activeMotionFPS)*0.9 { return }
        if motionKind == "notice" && !notificationActive { stopLighting(restore:true); return }
        let notice = notificationActive ? motionNotice.colors(layout:layout,background:[:],time:now-notificationStarted,pulse:true) : nil
        activeNoticeColors = notice
        let frame = LightingComposer.frame(base:motionBase(at:now),agent:pinnedAgentColors,reservedAgentKeys:agentPinned ? pinnedAgentKeys : [],notificationKeys:notificationActive ? Set(motionNotice.keys).subtracting(agentPinned ? pinnedAgentKeys : []) : [],notice:notice)
        // Live controllers may fall back to firmware when frames stop. Keep a
        // 250ms heartbeat even for silence/unchanged colors; never queue frames.
        if frame == lastMotionFrame, let lastMotionWrite, now-lastMotionWrite < 0.25 { return }
        let generation = liveGeneration
        do {
            let reports = try RKCodec.liveColors(layout:layout,colors:frame)
            liveInFlight = true; lastMotionSubmitted = now
            hid.sendLive(reports) { [weak self] result in
                guard let self, generation == self.liveGeneration else { return }
                self.liveInFlight = false
                switch result {
                case .success:
                    self.lastMotionFrame = frame; self.lastMotionWrite = self.lightingClock()
                    self.motionFramesWritten += 1
                case .failure(let failure):
                    self.stopLighting(restore:false); self.musicLightingEnabled = false
                    self.error = failure.localizedDescription; self.perform { throw failure }
                }
            }
        } catch { self.error = error.localizedDescription; stopLighting(restore:false) }
    }
    func stopLighting(restore: Bool = true) {
        let wasRunning = lightingActive
        liveGeneration += 1; liveInFlight = false
        motionTimer?.invalidate(); motionTimer = nil; lightingActive = false; lastMotionFrame = nil; lastMotionSubmitted = nil
        if wasRunning { hid.endColorStream() }
        if wasRunning { motionStatus = "实时灯光已停用" }
        if wasRunning && motionKind == "notice" && notificationActive { cancelNotification(restore: false) }
        if restore && wasRunning && connected, let reports = appliedReports {
            // Restore the latest quota/base snapshot, never the one captured at start.
            perform {
                if notificationActive {
                    let keys = Set(motionNotice.keys).subtracting(agentPinned ? pinnedAgentKeys : [])
                    let frame = LightingComposer.frame(base: appliedColors ?? emptyFrame, agent: pinnedAgentColors, reservedAgentKeys: agentPinned ? pinnedAgentKeys : [], notificationKeys: keys, notice: motionNotice.colors(layout: layout, background: [:], time: lightingClock()-notificationStarted, pulse: true))
                    try hid.send(RKCodec.customLighting(layout: layout, colors: frame, sleep: agentPinned ? 5 : appliedSettings.sleep))
                } else { try hid.send(reports) }
            }
        }
    }
    func saveAudioSensitivity() { preferences.set(audioSensitivity, forKey: "audioSensitivity") }
    func previewColors(time: Double) -> [Int: RGB] {
        if page == "Agent额度灯" { return LightingComposer.frame(base:baseColors ?? LightingComposer.base(layout:layout,settings:profile.light,pattern:.solid),agent:quotaColors,reservedAgentKeys:draftAgent.keys,notificationKeys:[],notice:nil) }
        if page == "音乐实验室" {
            let settings = appliedLight ? appliedSettings : profile.light
            let music = MotionRenderer.audioFrame(layout:layout,bands:audioBands,color:settings.color,rainbow:settings.rainbow,brightness:Double(settings.brightness)/5)
            return LightingComposer.frame(base:music,agent:pinnedAgentColors,reservedAgentKeys:agentPinned ? pinnedAgentKeys : [],notificationKeys:notificationActive ? effectiveNotificationKeys : [],notice:activeNoticeColors)
        }
        let base = LightingComposer.base(layout: layout, settings: profile.light, pattern: basicPattern, time: time)
        let showNotice = (page == "灯效与通知" && lightingTab == 1 && notificationPreview) || notificationActive
        return LightingComposer.frame(base: base, agent: pinnedAgentColors, reservedAgentKeys: agentPinned ? pinnedAgentKeys : [], notificationKeys: showNotice ? effectiveNotificationKeys : [], notice: showNotice ? notificationSettings.colors(layout: layout, background: [:], time: time, pulse: true) : nil)
    }
    var previewIsAnimated: Bool {
        (page == "音乐实验室" && audioPlaying) || (page == "灯效与通知" && (basicPattern.motion != nil || (lightingTab == 1 && notificationPreview)))
    }
    func accessibilityPermissions() {
        SystemBannerMonitor.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func testSystemBanner() {
        guard systemNotificationsEnabled else { return }
        BannerTest.shared.send { [weak self] success in
            self?.systemNotificationStatus = success ? "系统测试横幅将在 2 秒后出现，请观察键盘。" : "系统测试横幅未发送：请允许 FeralKey 的通知权限。"
        }
    }
    func stopSystemNotifications() {
        systemNotificationsEnabled = false; bannerMonitor?.stop(); bannerMonitor = nil
        systemNotificationStatus = "系统横幅监听已停止"
    }
    func setSystemNotifications(_ enabled: Bool) {
        if !enabled { preferredNotifications = false; stopSystemNotifications(); return }
        guard connected, appliedLight else { error = "请先连接键盘并应用一次灯光，作为通知显示的基础。"; return }
        guard notificationSettings.pattern.motion == nil || dynamicNotificationsEnabled else { error = "当前选择了动态通知，请先开启「实体动态通知（实验）」，或改用静态图案。"; return }
        guard SystemBannerMonitor.hasPermission else {
            systemNotificationStatus = "请在辅助功能中允许 FeralKey，然后重新开启监听。"
            accessibilityPermissions(); return
        }
        requestWrite("启用系统横幅监听：新通知在选定键区显示 5 秒，静态图案自动呼吸。平时通知区随整体灯光，不读取消息正文。设置会保存并在下次连接恢复。" + liveProtocolNotice) { [weak self] in
            guard let self, self.connected, self.appliedLight else { return }
            self.authorizeLiveProtocol(); self.preferredNotifications = true; self.startBannerMonitor()
        }
    }
    private func startBannerMonitor() {
        guard connected, appliedLight, directStreamEnabled, SystemBannerMonitor.hasPermission else { return }
        stopSystemNotifications()
        let monitor = SystemBannerMonitor(onBanner: { [weak self] in
            guard let self, self.systemNotificationsEnabled else { return }
            self.lastSystemBanner = Date()
            guard self.connected, self.appliedLight else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if let last = self.lastNotificationAt, now-last < 10 { return }
            if self.notificationSettings.pattern.motion != nil && !self.dynamicNotificationsEnabled {
                self.systemNotificationStatus = "请开启实验动态通知。"; return
            }
            self.record("检测到新的系统横幅，触发通知区灯光（不读取正文）")
            self.notify()
        }, onStatus: { [weak self] status in
            guard let self, self.systemNotificationsEnabled, self.systemNotificationStatus != status else { return }
            self.systemNotificationStatus = status
        })
        self.bannerMonitor = monitor
        self.systemNotificationsEnabled = monitor.start()
        self.systemNotificationStatus = self.systemNotificationsEnabled ? "正在连接系统通知中心…" : "辅助功能权限未生效，请重新授权后重试。"
    }
    func setShortcutPreset(_ id: String) {
        guard let preset = ShortcutPreset.all.first(where: { $0.id == id }) else { return }
        chosenPreset = id; shortcutKey = preset.key; shortcutModifiers = preset.modifiers
    }
    func stageCustomShortcut() {
        perform {
            guard let selectedKey, layout.keys.first(where: { $0.id == selectedKey })?.keyCode != "Key_Fn" else { throw RKError.message("请选择一个可改写的实体键。") }
            let code = try ShortcutCode.encode(key: shortcutKey, modifiers: shortcutModifiers, codes: codes)
            profile.overrides[selectedKey] = code; save()
        }
    }
    func mappingTitle(_ value: UInt32) -> String {
        if let preset = ShortcutPreset.all.first(where: { (try? ShortcutCode.encode(key: $0.key, modifiers: $0.modifiers, codes: codes)) == value }) { return preset.title }
        if let name = layout.keys.first(where: { codes[$0.keyCode] == value })?.label { return name }
        let flags = value >> 16
        let prefix = [(UInt32(1),"⌃"),(2,"⇧"),(4,"⌥"),(8,"⌘")].filter { flags & $0.0 != 0 }.map(\.1).joined()
        let base = layout.keys.first(where: { codes[$0.keyCode] == value & 0xffff })?.label ?? "?"
        return prefix + base
    }
}
