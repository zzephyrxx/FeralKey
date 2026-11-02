// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main enum FeatureTests {
    static func main() throws {
        let root = URL(fileURLWithPath: "Resources").standardizedFileURL
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: root.appendingPathComponent("rk98-layout.json")))
        let codes = try JSONDecoder().decode([String:UInt32].self, from: Data(contentsOf: root.appendingPathComponent("keycodes.json")))
        var assertions = 0
        func check(_ ok: Bool, _ name: String) { precondition(ok, name); assertions += 1 }
        for preset in ShortcutPreset.all {
            let value = try ShortcutCode.encode(key: preset.key, modifiers: preset.modifiers, codes: codes)
            check(ShortcutCode.isSupported(value, codes: codes), "preset accepted")
            let reports = try RKCodec.keymap(layout: layout, codes: codes, overrides: [0:value])
            try RKCodec.validateTransaction(reports)
            check(Array(reports[0][5...8]) == [0,preset.modifiers,UInt8((codes[preset.key]! >> 8) & 255),0], "preset modifier and base golden bytes")
        }
        for modifier in UInt8(0)...15 {
            let value = try ShortcutCode.encode(key: "Key_V", modifiers: modifier, codes: codes)
            check(ShortcutCode.isSupported(value, codes: codes), "all combinations of four left modifiers")
        }
        for bad in [UInt32.max, 0x1000600, 0x100600, 0x080001] { check(!ShortcutCode.isSupported(bad, codes: codes), "unknown high bits / invalid HID rejected") }
        do { _ = try ShortcutCode.encode(key: "Key_Fn", modifiers: 8, codes: codes); fatalError("Fn chord accepted") } catch { assertions += 1 }
        let old = try JSONDecoder().decode(LabProfile.self, from: Data("{\"version\":1,\"light\":{\"mode\":17,\"speed\":3,\"brightness\":3,\"color\":{\"r\":75,\"g\":232,\"b\":184},\"rainbow\":false,\"sleep\":1},\"overrides\":{\"0\":525824},\"shortcutURL\":\"https://example.com\",\"shortcutName\":\"\"}".utf8))
        try old.validate(layout: layout, codes: codes)
        var settings = NotificationSettings.defaults(layout)
        try settings.validate(layout)
        check(settings.keys.count >= 16, "whole numpad default")
        let background = Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.id, RGB(r: 7,g: 8,b: 9)) })
        var fingerprints = Set<Data>()
        for pattern in NotificationPattern.allCases {
            settings.pattern = pattern
            let frame = settings.colors(layout: layout, background: background)
            for key in layout.keys where !settings.keys.contains(key.id) { check(frame[key.id] == background[key.id], "outside notification region retained") }
            let packets = try RKCodec.customLighting(layout: layout, colors: frame)
            try RKCodec.validateTransaction(packets)
            fingerprints.insert(Data(packets.flatMap { $0 }))
        }
        check(fingerprints.count == NotificationPattern.allCases.count, "three presets and free drawing produce different patterns")
        settings.keys = []
        do { try settings.validate(layout); fatalError("empty notification keys") } catch { assertions += 1 }
        check(AudioEnvelope.level(sumSquares: 0, count: 512) == 0, "silence")
        check(AudioEnvelope.level(sumSquares: .nan, count: 512) == 0, "nonfinite audio")
        check(AudioEnvelope.level(sumSquares: 512, count: 512) == 1, "unity RMS")
        check(abs(AudioEnvelope.level(sumSquares: 0.512, count: 512)-0.5) < 0.001, "minus 30dB is halfway in envelope range")
        check(RefreshSchedule.maximumAge(1800) == 3630, "30min refresh is not expired by old 3min limit")
        var palette = AgentPalette(); palette.fiveHour = RGB(r: 12,g: 34,b: 56); palette.weekly = RGB(r: 201,g: 123,b: 45); palette.warningColors = false
        check(QuotaRenderer.color(remaining: 5, weekly: false, palette: palette) == palette.fiveHour, "custom color even at low quota when warning disabled")
        check(QuotaRenderer.color(remaining: 90, weekly: true, palette: palette) == palette.weekly, "independent weekly color")
        palette.warningColors = true
        check(QuotaRenderer.color(remaining: 5, weekly: false, palette: palette) == RGB(r: 245,g: 65,b: 60), "optional low quota warning")
        let composed = LightingComposer.frame(base: [0:.mint, 6:.mint, 7:.mint, 91:.mint], agent: [6:palette.fiveHour,7:palette.weekly], reservedAgentKeys: [6,7], notificationKeys: [7,91], notice: [7:RGB(r: 255,g: 0,b: 0),91:RGB(r: 255,g: 0,b: 0)])
        check(composed[0] == .mint && composed[6] == palette.fiveHour && composed[7] == palette.weekly && composed[91] == RGB(r: 255,g: 0,b: 0), "agent priority and disjoint notice/base regions")
        check(LightingComposer.frame(base: background, agent: [:], reservedAgentKeys: [], notificationKeys: [91], notice: nil)[91] == QuotaRenderer.off, "idle notification zone is dark")
        check(BannerDeduplicator.newIDs(previous: nil, current: ["old"]).isEmpty, "ignore existing banners when starting")
        check(BannerDeduplicator.newIDs(previous: ["old"], current: ["old","new"]) == ["new"], "new banner only")
        check(BannerDeduplicator.newIDs(previous: ["old","new"], current: ["old","new"]).isEmpty, "unchanged banner not replayed")
        check(BasicPattern.marquee.title == "跑马灯", "marquee remains a basic effect")
        var dim = LightSettings(); dim.brightness = 1
        var bright = dim; bright.brightness = 5
        let dimFrame = LightingComposer.base(layout: layout, settings: dim, pattern: .solid)
        let brightFrame = LightingComposer.base(layout: layout, settings: bright, pattern: .solid)
        check(dimFrame[0]!.g < brightFrame[0]!.g, "base brightness remains adjustable without global dimming")
        dim.brightness = 0
        check(LightingComposer.base(layout: layout, settings: dim, pattern: .solid).values.allSatisfy { $0 == QuotaRenderer.off }, "zero base brightness")
        var multicolor = LightSettings(); multicolor.rainbow = true; multicolor.brightness = 5
        for pattern in BasicPattern.allCases {
            let frame = LightingComposer.base(layout:layout,settings:multicolor,pattern:pattern,time:1.3)
            let hues = Set(frame.values.filter { $0 != QuotaRenderer.off }.map { "\($0.r),\($0.g),\($0.b)" })
            check(hues.count > 3, "multicolor supported by \(pattern.title)")
            try RKCodec.validateTransaction(RKCodec.customLighting(layout:layout,colors:frame))
        }
        let spectrumColors = MotionRenderer.audioFrame(layout:layout,bands:[Double](repeating:1,count:24),color:.mint,rainbow:true)
        check(Set(spectrumColors.values.map { "\($0.r),\($0.g),\($0.b)" }).count > 3, "music inherits multicolor palette")
        check(MotionRenderer.audioFrame(layout:layout,bands:[1],color:.mint,rainbow:true,brightness:0).values.allSatisfy { $0 == QuotaRenderer.off }, "music respects zero base brightness")
        multicolor.brightness = 0
        check(LightingComposer.base(layout:layout,settings:multicolor,pattern:.solid).values.allSatisfy { $0 == QuotaRenderer.off }, "multicolor respects zero brightness")
        check(LightingRate.choices.contains(45) && LightingRate.choices.contains(60) && LightingRate.defaultFPS == 45, "higher frame-rate choices and conservative default")
        for pattern in BasicPattern.allCases {
            let frame = LightingComposer.base(layout: layout, settings: LightSettings(), pattern: pattern)
            try RKCodec.validateTransaction(RKCodec.customLighting(layout: layout, colors: frame))
        }
        for style in [MotionStyle.marquee, .codeRain] {
            var frames = Set<Data>()
            let keys = Set(NotificationSettings.defaults(layout).keys)
            for step in 0..<20 {
                let frame = MotionRenderer.frame(layout: layout, keys: keys, style: style, color: .mint, time: Double(step)*0.2)
                check(Set(frame.keys) == keys, "motion strictly clipped to selected region")
                frames.insert(Data(keys.sorted().flatMap { [frame[$0]!.r,frame[$0]!.g,frame[$0]!.b] }))
            }
            check(frames.count > 5, "preset is a temporal animation, not a static rain mask")
        }
        var reactor = AudioReactor()
        var steady = 0.0
        for _ in 0..<250 { steady = reactor.update(0.8) }
        check(steady < 0.55, "loud steady music no longer pins every bar high")
        let beat = reactor.update(1)
        check(beat > steady+0.25, "transient has visible headroom")
        for _ in 0..<40 { steady = reactor.update(0) }
        check(steady < 0.001, "silence releases without floor glow")
        check(MotionRenderer.audioFrame(layout: layout, bands: [], color: .mint).values.allSatisfy { $0 == QuotaRenderer.off }, "silent keyboard is dark")
        check(MotionRenderer.audioFrame(layout: layout, bands: [.nan], color: .mint).values.allSatisfy { $0 == QuotaRenderer.off }, "invalid samples fail dark")
        func tone(_ hz:Double,_ phase:Double = 0) -> [Double] {
            (0..<AudioSpectrumAnalyzer.sampleCount).map { sin(2*Double.pi*hz*Double($0)/48000+phase)*0.55 }
        }
        func spectrum(_ values:[Double]) -> [Double] {
            var analyzer = AudioSpectrumAnalyzer(); analyzer.append(values); return analyzer.bands(sampleRate:48000)
        }
        func strongest(_ values:[Double]) -> Int { values.indices.max { values[$0] < values[$1] }! }
        let bass = spectrum(tone(93.75)), voice = spectrum(tone(750)), treble = spectrum(tone(6000))
        check(strongest(bass) < strongest(voice) && strongest(voice) < strongest(treble), "actual PCM frequencies occupy distinct ascending fixed bands")
        check(strongest(treble) == strongest(spectrum(tone(6000,1.5))), "time/phase changes do not scroll frequency columns")
        check(spectrum([Double](repeating:0,count:4096)).allSatisfy { $0 == 0 }, "FFT silence is dark")
        check(spectrum([Double](repeating:0.7,count:4096)).allSatisfy { $0 == 0 }, "DC offset does not create fake bass")
        check(spectrum([Double](repeating:.nan,count:4096)).allSatisfy { $0 == 0 }, "invalid PCM fails dark")
        var partial = AudioSpectrumAnalyzer(); partial.append([0.5])
        check(partial.bands(sampleRate:48000).allSatisfy { $0 == 0 }, "incomplete sample window does not fabricate spectrum")
        partial.append(tone(750))
        check(partial.bands(sampleRate:.nan).allSatisfy { $0 == 0 }, "invalid sample rate fails dark")
        let mixed = spectrum(zip(tone(93.75),tone(6000)).map { $0+$1 })
        check(mixed[strongest(bass)] > 0.7 && mixed[strongest(treble)] > 0.7, "simultaneous bass and treble survive analysis")
        var gentle = AudioReactor(), agile = AudioReactor()
        var low = 0.0, high = 0.0
        for _ in 0..<400 { low = gentle.update(0.8,sensitivity:0.5); high = agile.update(0.8,sensitivity:2) }
        check(abs(low-high) < 0.001, "sensitivity does not act as a steady-height limit")
        low = gentle.update(0.86,sensitivity:0.5); high = agile.update(0.86,sensitivity:2)
        check(high > low+0.08, "high sensitivity detects smaller musical onsets")
        var at30 = AudioReactor(), at60 = AudioReactor()
        for _ in 0..<200 { _ = at30.update(0.8,interval:1.0/30) }
        for _ in 0..<400 { _ = at60.update(0.8,interval:1.0/60) }
        var release30 = 0.0, release60 = 0.0
        for _ in 0..<9 { release30 = at30.update(0,interval:1.0/30) }
        for _ in 0..<18 { release60 = at60.update(0,interval:1.0/60) }
        check(abs(release30-release60) < 0.0001, "doubling audio cadence preserves release time")
        let localFrame = MotionRenderer.audioFrame(layout:layout,bands:treble,color:.mint)
        check(localFrame == MotionRenderer.audioFrame(layout:layout,bands:treble,color:.mint), "same frequencies remain in the same keyboard columns")
        var planner = HIDWritePlanner()
        let rgbFrame = try RKCodec.customLighting(layout:layout,colors:background)
        check(try planner.packets(for:rgbFrame).count == 8, "initial RGB mode requires header")
        check(try planner.packets(for:rgbFrame).count == 8, "planning does not assume successful delivery")
        planner.didSend(rgbFrame)
        let changedFrame = try RKCodec.customLighting(layout:layout,colors:[0:.mint])
        check(try planner.packets(for:changedFrame) == Array(changedFrame.dropFirst()), "subsequent colors never reselect mode 14")
        let differentSleep = try RKCodec.customLighting(layout:layout,colors:background,sleep:5)
        check(try planner.packets(for:differentSleep).count == 8, "changed global settings reinitialize exactly once")
        planner.didSend([try RKCodec.lighting(LightSettings())])
        check(try planner.packets(for:rgbFrame).count == 8, "firmware-mode switch invalidates RGB state")
        planner.didSend(rgbFrame); planner.reset()
        check(try planner.packets(for:rgbFrame).count == 8, "reconnect resets sender state")
        var malformed = rgbFrame; malformed[2][2] = 99
        do { _ = try planner.packets(for:malformed); fatalError("invalid transaction reached planner") } catch { assertions += 1 }
        var pulseSettings = NotificationSettings.defaults(layout); pulseSettings.pattern = .solid
        let peak = pulseSettings.colors(layout:layout,background:background,time:0,pulse:true)
        let trough = pulseSettings.colors(layout:layout,background:background,time:0.8,pulse:true)
        let pulseKey = pulseSettings.keys[0]
        check(peak[pulseKey] == pulseSettings.color && trough[pulseKey]!.g > 0 && trough[pulseKey]!.g < peak[pulseKey]!.g, "static notice breathes smoothly without hard off/on")
        let live = try RKCodec.liveColors(layout:layout,colors:background)
        try RKCodec.validateLiveColors(live)
        check(Array(live[0].prefix(5)) == [10,7,1,6,0], "live protocol uses 0x06 and a leading data byte, not static-save header")
        var livePayload:[UInt8] = []
        for (index,packet) in live.enumerated() { livePayload += packet[(index == 0 ? 4 : 3)...] }
        check(livePayload.count == 433, "seven complete live packets")
        for key in layout.keys { check(Array(livePayload[(1+key.id*3)...(3+key.id*3)]) == [7,8,9], "live index is static buffer index times three plus one") }
        do { try RKCodec.validateLiveColors(Array(live.dropLast())); fatalError("partial live frame accepted") } catch { assertions += 1 }
        let defaults = QuotaZones.defaults(layout:layout)
        let migrated = QuotaZones.migrated(QuotaZones(fiveHour:Array(defaults.fiveHour.reversed()),weekly:Array(defaults.weekly.reversed())),layout:layout)
        check(migrated == defaults, "old click-order layouts migrate to left-to-right thresholds")
        let oldCustom = layout.keys.first { $0.keyCode == "Key_A" }!.id
        let filled = QuotaZones.migrated(QuotaZones(fiveHour:[oldCustom],weekly:defaults.weekly),layout:layout)
        check(filled.fiveHour.count == 10 && filled.fiveHour.contains(oldCustom), "incomplete legacy layout keeps chosen keys and fills slots")
        check(filled.fiveHour[0] != oldCustom, "filled legacy layout is sorted again, not appended in a mixed order")
        let onlyFive = AgentConfiguration(zones:defaults,palette:AgentPalette(),display:AgentDisplay(fiveHourEnabled:true,weeklyEnabled:false))
        for step in 0...10 {
            let colors = onlyFive.colors(fiveHour:Double(step*10),weekly:nil)
            check(colors.values.filter { $0 != QuotaRenderer.off }.count == step, "each configured segment represents exactly ten percent")
            check(Set(colors.keys) == Set(defaults.fiveHour), "disabled weekly keys are released")
        }
        print("PASS: \(assertions) shortcut / notification pattern / audio envelope / refresh-policy checks (offline).")
    }
}
