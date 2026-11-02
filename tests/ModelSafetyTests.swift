// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

class MockKeyboardTransport: KeyboardTransport {
    var connected = false
    var writesAuthorized = false
    var openCount = 0
    var transactions: [[[UInt8]]] = []
    var failNextSend = false
    var streaming = false
    var scanResults = [[String:Any]]()
    func beginColorStream() { streaming = true }
    func endColorStream() { streaming = false }
    func sendLive(_ reports:[[UInt8]],completion:@escaping (Result<Void,Error>)->Void) { completion(Result { try send(reports) }) }
    func scan() -> [[String: Any]] { scanResults }
    func open() throws { openCount += 1; connected = true }
    func close() { connected = false }
    func send(_ reports: [[UInt8]]) throws {
        guard connected, writesAuthorized else { throw RKError.message("mock closed") }
        if failNextSend { failNextSend = false; connected = false; throw RKError.message("mock disconnected") }
        if reports.count == 7 { precondition(streaming); try RKCodec.validateLiveColors(reports) }
        else { try RKCodec.validateTransaction(reports) }
        transactions.append(reports)
    }
}

final class DelayedLiveTransport: MockKeyboardTransport {
    var submitted = 0
    var callbacks: [(Result<Void,Error>)->Void] = []
    override func sendLive(_ reports:[[UInt8]],completion:@escaping (Result<Void,Error>)->Void) {
        submitted += 1; callbacks.append(completion)
    }
    func completeFirst() { callbacks.removeFirst()(.success(())) }
}

@main enum ModelSafetyTests {
    static func main() throws {
        let resources = URL(fileURLWithPath: "Resources").standardizedFileURL
        let suite = "feralkey-tests-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(ResearchNotice.version, forKey: "researchConsentVersion")
        preferences.set(false, forKey: "restoreOnConnect")
        preferences.set(1,forKey:"liveProtocolConsent")
        func model(root: URL? = resources) -> (LabModel, MockKeyboardTransport) {
            let hid = MockKeyboardTransport()
            return (LabModel(resourceRoot: root, preferences: preferences, transport: hid, enumerateOnStart: false), hid)
        }
        let manualSuite = "feralkey-manual-music-"+UUID().uuidString
        let manualPreferences = UserDefaults(suiteName:manualSuite)!
        defer { manualPreferences.removePersistentDomain(forName:manualSuite) }
        manualPreferences.set(true,forKey:"preferredMusicLighting")
        manualPreferences.set(true,forKey:"audioAutoStart")
        let manualMusicHID = MockKeyboardTransport()
        let manualMusic = LabModel(resourceRoot:resources,preferences:manualPreferences,transport:manualMusicHID,enumerateOnStart:false)
        manualMusic.navigate("音乐实验室"); manualMusic.startSystemAudio()
        precondition(!manualMusic.musicRequested && !manualMusic.musicLightingEnabled && !manualMusic.audioPlaying && !manualMusic.audioStarting)
        precondition(manualMusicHID.transactions.isEmpty, "old enabled preferences and page entry must never enable music")
        manualMusic.cleanup()
        print("PASS: music requires a manual session switch; legacy autostart flags, page entry and unrequested capture remain off.")
        let receiverHID = MockKeyboardTransport()
        receiverHID.scanResults = [["VendorID":0x25a7,"ProductID":0xfa70]]
        let receiverModel = LabModel(resourceRoot:resources,preferences:manualPreferences,transport:receiverHID,enumerateOnStart:false)
        receiverModel.scan()
        precondition(receiverModel.receiverOnly && receiverModel.receiverDetected && !receiverModel.detected && !receiverModel.connected)
        precondition(receiverModel.status.contains("2.4G") && receiverModel.status.contains("尚未找到"))
        precondition(receiverHID.openCount == 0 && receiverHID.transactions.isEmpty, "recognition does not open receiver or send wired packets")
        receiverHID.scanResults.append(["VendorID":0x258a,"ProductID":0x00c1]); receiverModel.scan()
        precondition(receiverModel.detected && receiverModel.receiverDetected && !receiverModel.receiverOnly, "wired capability takes priority when both are present")
        receiverModel.cleanup()
        let (missing, missingHID) = model(root: nil)
        precondition(missing.startupError != nil && !missing.resourcesReady)
        missing.connect(); missing.applyLight(); missing.approveWrite(); missing.resetMapping(); missing.notify()
        precondition(missingHID.openCount == 0 && missingHID.transactions.isEmpty)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("feralkey-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent("rk98-layout.json"))
        let (invalid, invalidHID) = model(root: directory)
        invalid.connect(); invalid.applyMapping(); invalid.approveWrite()
        precondition(invalid.startupError != nil && invalidHID.transactions.isEmpty && invalidHID.openCount == 0)

        var corrupt = LabProfile(); corrupt.overrides[65] = UInt32.max
        preferences.set(try JSONEncoder().encode(corrupt), forKey: "labProfile")
        let (loaded, _) = model()
        precondition(loaded.profile.overrides.isEmpty, "invalid persisted profile must not be restored")
        preferences.removeObject(forKey: "labProfile")

        let (url, urlHID) = model()
        url.connect(); url.applyLight(); url.approveWrite()
        let beforeURL = urlHID.transactions.count
        url.handleURL(URL(string: "feralkey://focus")!)
        precondition(url.remaining == 0 && url.writePrompt != nil, "URL focus must wait for approval before scheduling a future write")
        url.cancelWrite()
        url.handleURL(URL(string: "feralkey://notify")!)
        precondition(urlHID.transactions.count == beforeURL && url.writePrompt != nil, "URL must wait for operation approval")
        url.cancelWrite()
        precondition(urlHID.transactions.count == beforeURL)
        url.handleURL(URL(string: "feralkey://notify")!); url.approveWrite()
        precondition(urlHID.transactions.count == beforeURL + 1)
        url.notify()
        precondition(urlHID.transactions.count == beforeURL + 1, "all notification paths share cooldown")
        url.connect()
        precondition(!url.appliedLight && !url.notificationActive)
        RunLoop.current.run(until: Date().addingTimeInterval(5.2))
        precondition(urlHID.transactions.count == beforeURL + 1, "old restore must not write to reconnected device")
        url.notify()
        precondition(urlHID.transactions.count == beforeURL + 1, "new connection has no inherited baseline")
        url.cleanup()

        let (failure, failureHID) = model()
        failure.connect(); failure.applyLight(); failure.approveWrite()
        failure.startFocus()
        failureHID.failNextSend = true
        failure.notify()
        precondition(!failure.appliedLight && !failure.notificationActive && !failure.connected && failure.remaining == 0, "send failure revokes session and scheduled work")
        failure.cleanup()
        var writeTime: TimeInterval = 100
        let liveHID = MockKeyboardTransport()
        let automatic = LabModel(resourceRoot: resources, preferences: preferences, transport: liveHID, enumerateOnStart: false, quotaWriteClock: { writeTime })
        automatic.connect(); automatic.quotaAutoRefresh = true
        func quota(_ used: Double) -> QuotaSnapshot {
            let reset = Date().addingTimeInterval(7200).timeIntervalSince1970
            return QuotaSnapshot(buckets: ["codex": QuotaBucket(limitId: "codex", limitName: nil, primary: QuotaWindow(usedPercent: used, windowDurationMins: 300, resetsAt: reset), secondary: QuotaWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: reset))], fetchedAt: Date(), isDemo: false)
        }
        automatic.quota = quota(20); automatic.quotaNow = Date()
        automatic.setQuotaHardwareAuto(true)
        precondition(liveHID.transactions.isEmpty && !automatic.quotaHardwareAuto)
        automatic.approveWrite()
        precondition(automatic.quotaHardwareAuto && liveHID.transactions.count == 1)
        automatic.syncQuotaAutomaticallyIfNeeded()
        precondition(liveHID.transactions.count == 1, "same color frame skipped")
        automatic.setQuotaInterval(30)
        automatic.quota = quota(50); writeTime += 29
        automatic.syncQuotaAutomaticallyIfNeeded()
        precondition(liveHID.transactions.count == 1, "interval protects hardware writes")
        writeTime += 1; automatic.syncQuotaAutomaticallyIfNeeded()
        precondition(liveHID.transactions.count == 2, "changed frame syncs after chosen interval")
        let quotaReports = liveHID.transactions.last!
        automatic.notify()
        precondition(liveHID.transactions.count == 3 && automatic.notificationActive)
        automatic.quota = quota(70); writeTime += 30
        automatic.syncQuotaAutomaticallyIfNeeded()
        precondition(liveHID.transactions.count == 3, "automatic quota defers to notification")
        RunLoop.current.run(until: Date().addingTimeInterval(5.2))
        precondition(liveHID.transactions.last! == quotaReports && !automatic.notificationActive, "notification restores whole previous RGB frame")
        automatic.setQuotaInterval(1800)
        automatic.quota = QuotaSnapshot(buckets: quota(10).buckets, fetchedAt: Date().addingTimeInterval(-600), isDemo: false)
        precondition(automatic.quotaRemaining(300) == 90, "30min policy keeps 10min data valid")
        automatic.stopQuota()
        precondition(!automatic.quotaHardwareAuto && !automatic.quotaAutoRefresh)
        automatic.demoQuota()
        RunLoop.current.run(until:Date().addingTimeInterval(0.25))
        precondition(preferences.string(forKey:"quotaBucket") != "demo", "demo source must not replace saved real quota source")
        automatic.syncQuotaAutomaticallyIfNeeded()
        precondition(liveHID.transactions.last! == quotaReports, "demo cannot auto write")
        automatic.connect()
        precondition(!automatic.quotaHardwareAuto && !automatic.appliedLight)
        automatic.cleanup()
        let pinHID = MockKeyboardTransport()
        let pinned = LabModel(resourceRoot: resources, preferences: preferences, transport: pinHID, enumerateOnStart: false, quotaWriteClock: { writeTime })
        pinned.connect(); pinned.setQuotaInterval(30); pinned.quotaAutoRefresh = true; pinned.quota = quota(20); pinned.quotaNow = Date()
        pinned.agentPalette.fiveHour = RGB(r: 12,g: 34,b: 56); pinned.agentPalette.warningColors = false
        pinned.applyAgentConfiguration(); pinned.approveWrite()
        let beforePinApproval = pinHID.transactions.count
        pinned.setAgentPinned(true); precondition(!pinned.agentPinned && pinHID.transactions.count == beforePinApproval)
        pinned.approveWrite(); precondition(pinned.agentPinned)
        precondition(pinHID.transactions.last![0][13] == 5, "pinned quota requests firmware lighting sleep off")
        func color(_ reports: [[UInt8]], key: Int) -> RGB {
            precondition(reports.count == 8 || reports.count == 7)
            var payload: [UInt8] = []
            let live = reports.count == 7
            for (index, report) in (live ? reports : Array(reports.dropFirst())).enumerated() { payload += report[(index == 0 ? (live ? 4 : 6) : 3)...] }
            let offset = key*3+(live ? 1 : 0)
            return RGB(r: payload[offset], g: payload[offset+1], b: payload[offset+2])
        }
        let agentKey = pinned.quotaZones.fiveHour[0], agentSecond = pinned.quotaZones.fiveHour[1]
        let noticeKey = pinned.layout.keys.first { $0.keyCode == "Key_Num_7" }!.id
        let baseKey = pinned.layout.keys.first { $0.keyCode == "Key_A" }!.id
        let agentColor = pinned.agentPalette.fiveHour
        pinned.profile.light.color = RGB(r: 90,g: 100,b: 110); pinned.profile.light.mode = 9; pinned.profile.light.brightness = 5
        pinned.applyLight(); pinned.approveWrite()
        precondition(pinned.agentPinned && pinned.quotaHardwareAuto)
        precondition(pinHID.transactions.last![0][13] == 5, "base sleep setting cannot dim pinned agent")
        precondition(color(pinHID.transactions.last!, key: agentKey) == agentColor, "base application must preserve pinned agent color")
        precondition(color(pinHID.transactions.last!, key: noticeKey) == pinned.profile.light.color, "idle notice keys participate in the base effect")
        precondition(color(pinHID.transactions.last!, key: baseKey) == pinned.profile.light.color)
        pinned.profile.light.brightness = 0; pinned.applyLight(); pinned.approveWrite()
        precondition(color(pinHID.transactions.last!, key: baseKey) == QuotaRenderer.off)
        precondition(color(pinHID.transactions.last!, key: agentKey) == agentColor, "base brightness zero must not turn off reserved agent")
        pinned.profile.light.brightness = 5; pinned.applyLight(); pinned.approveWrite()
        pinned.notificationSettings.pattern = .solid
        pinned.notify()
        precondition(color(pinHID.transactions.last!, key: agentKey) == agentColor)
        precondition(color(pinHID.transactions.last!, key: noticeKey) == pinned.notificationSettings.color)
        precondition(color(pinHID.transactions.last!, key: baseKey) == pinned.profile.light.color)
        pinned.quota = quota(90); writeTime += 30
        pinned.syncQuotaAutomaticallyIfNeeded()
        precondition(pinned.notificationActive)
        precondition(color(pinHID.transactions.last!, key: noticeKey) == pinned.notificationSettings.color, "agent refresh must not clear active notice")
        precondition(color(pinHID.transactions.last!, key: agentSecond) == QuotaRenderer.off)
        RunLoop.current.run(until: Date().addingTimeInterval(5.2))
        precondition(color(pinHID.transactions.last!, key: noticeKey) == pinned.profile.light.color)
        precondition(color(pinHID.transactions.last!, key: agentSecond) == QuotaRenderer.off, "notice end must not restore old quota")
        pinned.page = "灯效与通知"; pinned.lightingTab = 1; pinned.notificationEditing = true
        let before = pinned.notificationSettings.keys
        pinned.selectKey(pinned.layout.keys.first { $0.id == agentKey }!)
        precondition(pinned.notificationSettings.keys == before, "reserved agent key cannot become notice key")
        pinned.setAgentPinned(false); pinned.separateNotificationRegion = false; pinned.basicPattern = .solid
        pinned.profile.light.rainbow = true; pinned.applyLight(); pinned.approveWrite()
        precondition(pinHID.transactions.last!.count == 8 && pinned.quotaDisplay.fiveHourEnabled && pinned.quotaDisplay.weeklyEnabled, "multicolor base never disables Agent groups")
        precondition(color(pinHID.transactions.last!,key:agentKey) == agentColor, "multicolor base keeps the latest applied Agent color")
        pinned.cleanup()
        let (motion, motionHID) = model()
        motion.motionFPS = 20
        motion.connect(); motion.profile.light.rainbow = true
        motion.quota = quota(20); motion.quotaAutoRefresh = true; motion.quotaNow = Date()
        motion.quotaDisplay = AgentDisplay(); motion.applyAgentConfiguration(); motion.approveWrite()
        motion.setAgentPinned(true); motion.approveWrite()
        motion.setBaseColor(RGB(r: 4,g: 70,b: 200))
        precondition(!motion.profile.light.rainbow, "choosing a fixed color disables random-color firmware flag")
        motion.profile.light.brightness = 5
        motion.setBasePattern(.solid); motion.applyLight(); motion.approveWrite()
        precondition(color(motionHID.transactions.last!, key: baseKey) == RGB(r: 4,g: 70,b: 200), "color picker reaches exact per-key RGB bytes")
        let beforeMotionApproval = motionHID.transactions.count
        motion.setBasePattern(.codeRain); motion.applyLight()
        precondition(motionHID.transactions.count == beforeMotionApproval && !motion.lightingActive, "preview/selection cannot start writes before confirmation")
        motion.approveWrite(); precondition(motion.lightingActive)
        motion.tickLighting()
        precondition(color(motionHID.transactions.last!, key: motion.quotaZones.fiveHour[0]) == motion.agentPalette.fiveHour, "animated base must preserve pinned quota keys")
        let countAfterFirstTick = motionHID.transactions.count
        for _ in 0..<20 { motion.tickLighting() }
        precondition(motionHID.transactions.count == countAfterFirstTick, "physical animation has a monotonic target-FPS write ceiling")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        precondition(motion.motionFramesWritten >= 8 && motion.motionFramesWritten <= 14)
        RunLoop.current.run(until:Date().addingTimeInterval(15.1))
        precondition(motion.lightingActive, "applied code rain must continue beyond the retired 15-second trial")
        precondition(motionHID.transactions.suffix(20).allSatisfy { $0.count == 7 && $0[0][3] == 6 }, "continuous animation never uses static-save RGB transactions")
        motion.audioPlaying = true; motion.audioBands = [Double](repeating:0.7,count:AudioSpectrumAnalyzer.bandCount)
        motion.setMusicLighting(true); motion.approveWrite()
        precondition(motion.musicLightingEnabled && motion.musicRequested && motion.lightingActive)
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        precondition(color(motionHID.transactions.last!,key:baseKey) != QuotaRenderer.off, "enabled music renders incoming audio")
        motion.page = "音乐实验室"
        let musicAgentKey = motion.quotaZones.fiveHour[0]
        precondition(motion.previewColors(time:0)[musicAgentKey] == color(motionHID.transactions.last!,key:musicAgentKey), "music keyboard preview shows the same pinned Agent color as physical output")
        motion.audioBands = [Double](repeating:0,count:AudioSpectrumAnalyzer.bandCount)
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        precondition(color(motionHID.transactions.last!,key:baseKey) == QuotaRenderer.off, "silence changes live music frame")
        motion.setMusicLighting(false)
        precondition(!motion.musicLightingEnabled && !motion.musicRequested)
        motion.connect()
        let closedCount = motionHID.transactions.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        precondition(!motion.lightingActive && motion.motionFramesWritten == 0 && motionHID.transactions.count == closedCount, "reconnect cancels animation and old restore callbacks")
        motion.setBasePattern(.solid); motion.applyLight(); motion.approveWrite()
        motion.notificationSettings.pattern = .codeRain
        motion.setDynamicNotifications(true); precondition(!motion.dynamicNotificationsEnabled)
        motion.approveWrite(); motion.notify()
        precondition(motion.lightingActive && motion.notificationActive)
        RunLoop.current.run(until: Date().addingTimeInterval(5.3))
        precondition(!motion.lightingActive && !motion.notificationActive, "notice must end after five seconds; active=\(motion.lightingActive), notice=\(motion.notificationActive), frames=\(motion.motionFramesWritten), fps=\(motion.motionFPS)")
        precondition(motion.motionFramesWritten <= Int(Double(motion.motionFPS)*5*1.1)+1, "unexpected live-frame rate: \(motion.motionFramesWritten)")
        motion.cleanup()
        let savedSuite = "feralkey-persistence-" + UUID().uuidString
        let saved = UserDefaults(suiteName:savedSuite)!
        defer { saved.removePersistentDomain(forName:savedSuite) }
        saved.set(ResearchNotice.version,forKey:"researchConsentVersion")
        let firstHID = MockKeyboardTransport()
        let first = LabModel(resourceRoot:resources,preferences:saved,transport:firstHID,enumerateOnStart:false)
        first.connect(); first.profile.light.brightness = 5; first.setBaseColor(RGB(r:10,g:20,b:30))
        first.applyLight(); first.approveWrite()
        first.quota = quota(20); first.quotaNow = Date()
        first.applyAgentConfiguration(); first.approveWrite()
        // A pending edit must persist in the interface without becoming the
        // successful hardware snapshot that gets replayed after restart.
        first.setBaseColor(RGB(r:90,g:80,b:70)); first.motionFPS = 20
        first.focusMinutes = 47; first.chosenPreset = "custom"; first.shortcutKey = "Key_K"; first.shortcutModifiers = 9
        first.page = "灯效与通知"; first.lightingTab = 1
        first.preferredAgentPinned = true; first.preferredHardwareAuto = true; first.preferredDynamicNotifications = true
        first.agentPalette.weekly = RGB(r:15,g:45,b:75)
        first.notificationSettings.pattern = .checkerboard
        RunLoop.current.run(until:Date().addingTimeInterval(0.55))
        let resumedHID = MockKeyboardTransport()
        let resumed = LabModel(resourceRoot:resources,preferences:saved,transport:resumedHID,enumerateOnStart:false)
        precondition(resumed.profile.light.color == RGB(r:90,g:80,b:70) && resumed.motionFPS == 20 && resumed.focusMinutes == 47)
        precondition(resumed.page == "灯效与通知" && resumed.lightingTab == 1 && resumed.shortcutKey == "Key_K" && resumed.shortcutModifiers == 9)
        precondition(resumed.agentPalette.weekly == RGB(r:15,g:45,b:75) && resumed.notificationSettings.pattern == .checkerboard)
        precondition(resumed.preferredAgentPinned && resumed.preferredHardwareAuto && !resumed.agentPinned, "intent is saved independently from live device state")
        resumed.connect()
        precondition(resumed.appliedLight && !resumed.lightingActive && resumed.dynamicNotificationsEnabled)
        precondition(color(resumedHID.transactions.last!,key:baseKey) == RGB(r:10,g:20,b:30), "restart replays successful applied color, not unsent edit")
        resumed.quota = quota(20); resumed.quotaNow = Date(); resumed.quotaAutoRefresh = true
        resumed.syncQuotaAutomaticallyIfNeeded()
        precondition(resumed.agentPinned && resumed.quotaHardwareAuto, "saved pin waits for fresh real quota before resuming")
        precondition(resumedHID.transactions.allSatisfy { $0.count != 9 }, "restart never replays whole keyboard mappings")
        resumed.setQuotaHardwareAuto(false); resumed.persistUserSettings()
        let pausedHID = MockKeyboardTransport()
        let paused = LabModel(resourceRoot:resources,preferences:saved,transport:pausedHID,enumerateOnStart:false)
        paused.connect(); paused.quota = quota(20); paused.quotaNow = Date(); paused.quotaAutoRefresh = true
        paused.syncQuotaAutomaticallyIfNeeded()
        precondition(paused.agentPinned && !paused.quotaHardwareAuto && !paused.preferredHardwareAuto, "saved pin cannot override user's disabled hardware-auto choice")
        resumedHID.failNextSend = true; resumed.connect()
        precondition(!resumed.connected && resumed.preferredAgentPinned && !resumed.preferredHardwareAuto, "failed restoration keeps user choices")
        first.cleanup(); resumed.cleanup(); paused.cleanup()
        let agentSuite = "feralkey-agent-config-" + UUID().uuidString
        let agentPreferences = UserDefaults(suiteName:agentSuite)!
        defer { agentPreferences.removePersistentDomain(forName:agentSuite) }
        agentPreferences.set(ResearchNotice.version,forKey:"researchConsentVersion")
        let agentHID = MockKeyboardTransport(); var agentClock = 0.0
        let agent = LabModel(resourceRoot:resources,preferences:agentPreferences,transport:agentHID,enumerateOnStart:false,quotaWriteClock:{agentClock})
        agent.connect(); agent.profile.light.brightness = 5; agent.setBaseColor(RGB(r:100,g:200,b:50)); agent.applyLight(); agent.approveWrite()
        func oneWindow(_ minutes:Int,_ used:Double) -> QuotaSnapshot {
            let window = QuotaWindow(usedPercent:used,windowDurationMins:minutes,resetsAt:Date().addingTimeInterval(7200).timeIntervalSince1970)
            return QuotaSnapshot(buckets:["codex":QuotaBucket(limitId:"codex",limitName:nil,primary:minutes == 300 ? window : nil,secondary:minutes == 10080 ? window : nil)],fetchedAt:Date(),isDemo:false)
        }
        agent.quota = oneWindow(300,10); agent.quotaNow = Date(); agent.quotaDisplay.weeklyEnabled = false
        precondition(agent.canApplyAgent && !agent.canSyncQuota, "disabled missing window must not block applying the other window")
        agent.applyAgentConfiguration(); agent.approveWrite()
        let weeklyKey = agent.quotaZones.weekly[0], fiveKey = agent.quotaZones.fiveHour[0]
        precondition(color(agentHID.transactions.last!,key:weeklyKey) == RGB(r:100,g:200,b:50), "disabled weekly returns to base")
        let appliedFiveColor = agent.agentPalette.fiveHour
        agent.profile.light.brightness = 0; agent.applyLight(); agent.approveWrite()
        precondition(color(agentHID.transactions.last!,key:fiveKey) == appliedFiveColor, "base settings preserve an applied enabled quota even without extra pin priority")
        agent.profile.light.brightness = 5; agent.applyLight(); agent.approveWrite()
        agent.quotaAutoRefresh = true; agent.setQuotaInterval(30); agent.setQuotaHardwareAuto(true); agent.approveWrite()
        agent.agentPalette.fiveHour = RGB(r:255,g:0,b:0); agent.quotaDisplay.weeklyEnabled = true
        agent.quota = oneWindow(300,40); agentClock += 30; agent.syncQuotaAutomaticallyIfNeeded()
        precondition(color(agentHID.transactions.last!,key:fiveKey) == appliedFiveColor, "draft palette does not leak into auto updates")
        precondition(!agent.canApplyAgent && agent.canSyncQuota, "draft enabled missing window cannot change applied single-window config")
        agent.quota = oneWindow(10080,50); agent.quotaNow = Date(); agent.quotaDisplay.fiveHourEnabled = false
        agent.applyAgentConfiguration(); agent.approveWrite()
        precondition(color(agentHID.transactions.last!,key:fiveKey) == RGB(r:100,g:200,b:50), "weekly-only does not require five-hour data")
        agent.page = "Agent额度灯"; agent.quotaEditing = 1; agent.quotaSlot = 0
        let customKey = agent.layout.keys.first { $0.keyCode == "Key_A" }!
        agent.selectKey(customKey)
        precondition(agent.quotaZones.fiveHour[0] == customKey.id && agent.quotaMarker(customKey.id) == "10%")
        try agent.quotaZones.validate(layout:agent.layout)
        agent.quotaDisplay.weeklyEnabled = false; agent.quota = nil
        precondition(agent.canApplyAgent, "turning both off requires no account data")
        agent.applyAgentConfiguration(); agent.approveWrite()
        precondition(!agent.canSyncQuota && !agent.quotaHardwareAuto && !agent.preferredHardwareAuto)
        agent.cleanup()
        let delayedSuite = "feralkey-live-queue-" + UUID().uuidString
        let delayedPreferences = UserDefaults(suiteName:delayedSuite)!
        defer { delayedPreferences.removePersistentDomain(forName:delayedSuite) }
        delayedPreferences.set(ResearchNotice.version,forKey:"researchConsentVersion")
        delayedPreferences.set(1,forKey:"liveProtocolConsent"); delayedPreferences.set(false,forKey:"restoreOnConnect")
        let delayedHID = DelayedLiveTransport()
        let delayed = LabModel(resourceRoot:resources,preferences:delayedPreferences,transport:delayedHID,enumerateOnStart:false)
        delayed.connect(); delayed.setBasePattern(.codeRain); delayed.applyLight(); delayed.approveWrite(); delayed.tickLighting()
        for _ in 0..<50 { delayed.tickLighting() }
        precondition(delayedHID.submitted == 1, "busy USB may have only one pending frame")
        delayed.connect(); delayed.applyLight(); delayed.approveWrite(); delayed.tickLighting()
        precondition(delayedHID.submitted == 2)
        delayedHID.completeFirst()
        for _ in 0..<50 { delayed.tickLighting() }
        precondition(delayedHID.submitted == 2 && delayed.motionFramesWritten == 0, "old completion cannot release new session's in-flight gate")
        delayedHID.completeFirst()
        precondition(delayed.motionFramesWritten == 1 && delayed.lightingActive)
        delayed.cleanup()
        let cadenceSuite = "feralkey-cadence-"+UUID().uuidString
        let cadencePreferences = UserDefaults(suiteName:cadenceSuite)!
        defer { cadencePreferences.removePersistentDomain(forName:cadenceSuite) }
        cadencePreferences.set(ResearchNotice.version,forKey:"researchConsentVersion")
        cadencePreferences.set(1,forKey:"liveProtocolConsent"); cadencePreferences.set(false,forKey:"restoreOnConnect")
        cadencePreferences.set(30,forKey:"motionFPS"); cadencePreferences.set(1,forKey:"liveSettingsVersion")
        let cadenceHID = DelayedLiveTransport(); var frameTime = 100.0
        let cadence = LabModel(resourceRoot:resources,preferences:cadencePreferences,transport:cadenceHID,enumerateOnStart:false,lightingClock:{ frameTime })
        precondition(cadence.motionFPS == 45, "old 30 FPS default upgrades once to 45")
        cadence.connect(); cadence.profile.light.rainbow = true; cadence.setBasePattern(.breathing)
        cadence.setMotionFPS(60); cadence.applyLight(); cadence.approveWrite(); cadence.tickLighting()
        precondition(cadenceHID.submitted == 1 && cadence.profile.light.rainbow)
        frameTime += 0.010; cadenceHID.completeFirst()
        frameTime += 0.007; cadence.tickLighting()
        precondition(cadenceHID.submitted == 2, "10 ms USB latency must not halve a 60 FPS schedule")
        for _ in 0..<10 { cadence.tickLighting() }
        precondition(cadenceHID.submitted == 2, "one in-flight gate still applies at 60 FPS")
        frameTime += 0.010; cadenceHID.completeFirst()
        cadence.setMotionFPS(45); frameTime += 0.014; cadence.tickLighting()
        precondition(cadenceHID.submitted == 3 && cadence.motionStatus.contains("45"), "runtime rate changes take effect without reapplying lights")
        cadence.setMotionFPS(60); cadence.persistUserSettings(); cadence.cleanup()
        let rateReload = LabModel(resourceRoot:resources,preferences:cadencePreferences,transport:MockKeyboardTransport(),enumerateOnStart:false)
        precondition(rateReload.motionFPS == 60, "explicit high frame rate persists")
        rateReload.cleanup()
        var legacyLight = LightSettings(); legacyLight.mode = 9
        cadencePreferences.set(try JSONEncoder().encode(legacyLight),forKey:"lastAppliedLight")
        cadencePreferences.set("solid",forKey:"lastAppliedPattern"); cadencePreferences.set(true,forKey:"lastAppliedFirmware")
        cadencePreferences.set(true,forKey:"restoreOnConnect")
        let legacyHID = MockKeyboardTransport()
        let legacy = LabModel(resourceRoot:resources,preferences:cadencePreferences,transport:legacyHID,enumerateOnStart:false)
        legacy.connect()
        precondition(legacyHID.transactions.first?.count == 8 && legacy.quotaDisplay.fiveHourEnabled && legacy.quotaDisplay.weeklyEnabled, "legacy whole-board snapshot restores through composed base without disabling Agent groups")
        legacy.cleanup()
        print("PASS: 45/60 FPS cadence with simulated USB latency; runtime rate change; busy-frame drop; frame-rate migration and persistence.")
        print("PASS: live-frame backpressure and stale-session completion isolation.")
        print("PASS: independent quota windows; exact ten-percent slots; draft/apply isolation; disabled keys restored to base; no-data disable.")
        print("PASS: automatic preference persistence without explicit save; applied/draft separation; restart restore; fresh-quota pin resume; failure retains settings; no mapping replay.")
        print("PASS: fixed-color RGB bytes; continuous regional live animation; configurable FPS ceiling; reconnect cancellation; animated notice deadline and restoration (mock HID only).")
        print("PASS: missing/corrupt resources fail closed; persisted profile validation; URL approval/cooldown; reconnect cancels old restoration; device failure clears session (mock HID only).")
        print("PASS: opt-in quota auto sync, interval throttle, unchanged-frame dedup, notification priority/full-frame restore, long refresh intervals, demo and reconnect guards (mock HID only).")
        print("PASS: pinned agent palette survives multicolor base changes; isolated notice/base regions; concurrent quota/notice updates; no stale quota restoration (mock HID only).")
    }
}
