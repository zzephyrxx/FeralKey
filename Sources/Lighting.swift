// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct AgentPalette: Codable, Equatable {
    var fiveHour = RGB(r: 70, g: 212, b: 166)
    var weekly = RGB(r: 107, g: 150, b: 248)
    var warningColors = true
}

enum LightingRate {
    static let choices = [12,20,30,45,60]
    static let defaultFPS = 45
    static let maximumFPS = 60
}

enum RainbowPalette {
    static func color(position:Double) -> RGB {
        let hue = (position.isFinite ? position : 0).truncatingRemainder(dividingBy:1)
        let h = (hue < 0 ? hue+1 : hue)*6
        let sector = Int(h), fraction = h-Double(sector)
        let low = 0.08, rising = low+(1-low)*fraction, falling = 1-(1-low)*fraction
        let rgb:(Double,Double,Double)
        switch sector {
        case 0: rgb = (1,rising,low)
        case 1: rgb = (falling,1,low)
        case 2: rgb = (low,1,rising)
        case 3: rgb = (low,falling,1)
        case 4: rgb = (rising,low,1)
        default: rgb = (1,low,falling)
        }
        return RGB(r:UInt8(rgb.0*255),g:UInt8(rgb.1*255),b:UInt8(rgb.2*255))
    }
}

enum BasicPattern: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, rain, breathing, marquee, codeRain
    var id: String { rawValue }
    var title: String { switch self { case .solid: return "常亮"; case .gradient: return "渐变"; case .rain: return "静态雨滴"; case .breathing: return "呼吸"; case .marquee: return "跑马灯"; case .codeRain: return "代码雨" } }
    var motion: MotionStyle? { switch self { case .breathing: return .breathing; case .marquee: return .marquee; case .codeRain: return .codeRain; default: return nil } }
}

enum LightingComposer {
    static func base(layout: Layout, settings: LightSettings, pattern: BasicPattern, time: Double = 0) -> [Int: RGB] {
        if let style = pattern.motion {
            return MotionRenderer.frame(layout: layout, keys: Set(layout.keys.map(\.id)), style: style, color: settings.color, time: time, speed: Double(settings.speed), brightness: Double(settings.brightness)/5, rainbow:settings.rainbow)
        }
        return Dictionary(uniqueKeysWithValues: layout.keys.map { key in
            let scale: Double
            switch pattern {
            case .solid: scale = 1
            case .gradient: scale = 0.15 + 0.85 * min(1, key.top[0] / 830)
            case .rain: scale = (key.id * 17 + 13) % 11 < 3 ? 1 : ((key.id * 7) % 5 == 0 ? 0.3 : 0.04)
            case .breathing, .marquee, .codeRain: scale = 1
            }
            // Keep device-wide brightness constant when composing regions, so
            // the base brightness control cannot dim reserved Agent keys.
            let c = settings.rainbow ? RainbowPalette.color(position:key.top[0]/830) : settings.color
            let intensity = scale * Double(settings.brightness) / 5
            return (key.id, RGB(r: UInt8(Double(c.r)*intensity), g: UInt8(Double(c.g)*intensity), b: UInt8(Double(c.b)*intensity)))
        })
    }
    // Last writer to the device always sends a complete composed frame.
    // Agent > notification > base. Notification keys are dark when idle.
    static func frame(base: [Int: RGB], agent: [Int: RGB], reservedAgentKeys: Set<Int>, notificationKeys: Set<Int>, notice: [Int: RGB]?) -> [Int: RGB] {
        var output = base
        for key in notificationKeys { output[key] = notice?[key] ?? QuotaRenderer.off }
        for key in reservedAgentKeys { output[key] = agent[key] ?? QuotaRenderer.unknown }
        return output
    }
}

enum MotionStyle { case breathing, marquee, codeRain }

enum MotionRenderer {
    // Both regions share the same spatial renderer; no random state, file I/O
    // or device commands. Screen previews are independent of HID playback.
    static func frame(layout: Layout, keys: Set<Int>, style: MotionStyle, color: RGB, time: Double, speed: Double = 3, brightness: Double = 1, rainbow:Bool = false) -> [Int: RGB] {
        let chosen = layout.keys.filter { keys.contains($0.id) }
        guard !chosen.isEmpty else { return [:] }
        let minX = chosen.map { $0.top[0] }.min()!, maxX = chosen.map { $0.bottom[0] }.max()!
        let minY = chosen.map { $0.top[1] }.min()!, maxY = chosen.map { $0.bottom[1] }.max()!
        let t = (time.isFinite ? max(0, time) : 0) * min(5, max(1, speed)) / 3
        var output: [Int: RGB] = [:]
        for key in chosen {
            let x = ((key.top[0]+key.bottom[0])/2-minX)/max(1,maxX-minX)
            let y = ((key.top[1]+key.bottom[1])/2-minY)/max(1,maxY-minY)
            let level: Double
            switch style {
            case .breathing: level = 0.03 + 0.97 * pow((sin(t*2.8)+1)/2, 2)
            case .marquee:
                let head = (t*0.45).truncatingRemainder(dividingBy: 1.35)-0.15
                let distance = head-x
                level = distance >= 0 && distance < 0.28 ? pow(1-distance/0.28, 1.6) : 0
            case .codeRain:
                let column = Int(((key.top[0]+key.bottom[0])/2-minX)/43)
                let offset = Double((column*37+11)%17)/17
                let head = (t*(0.6+Double(column%3)*0.13)+offset*1.65).truncatingRemainder(dividingBy: 1.65)-0.2
                let distance = head-y
                level = distance >= 0 && distance < 0.42 ? pow(1-distance/0.42, 2) : 0
            }
            let intensity = min(1,max(0,level*brightness))
            let tint = rainbow ? RainbowPalette.color(position:x) : color
            output[key.id] = RGB(r: UInt8(Double(tint.r)*intensity), g: UInt8(Double(tint.g)*intensity), b: UInt8(Double(tint.b)*intensity))
        }
        return output
    }

    static func audioFrame(layout: Layout, bands: [Double], color: RGB, rainbow:Bool = false, brightness:Double = 1) -> [Int: RGB] {
        let maxX = layout.keys.map { $0.bottom[0] }.max() ?? 850
        let maxY = layout.keys.map { $0.bottom[1] }.max() ?? 310
        return Dictionary(uniqueKeysWithValues: layout.keys.map { key in
            let x = (key.top[0]+key.bottom[0])/2/maxX
            let y = 1-(key.top[1]+key.bottom[1])/2/maxY
            // The x-axis is frequency, never time. Every column responds in place.
            let index = min(max(0,bands.count-1), max(0,Int(x*Double(bands.count))))
            let sample = bands.isEmpty ? 0 : bands[index]
            let level = sample.isFinite ? min(1,max(0,sample)) : 0
            let coverage = min(1,max(0,(level-y)*5+0.5))
            let intensity = level > 0.015 ? coverage*(0.12+level*0.88)*min(1,max(0,brightness)) : 0
            let tint = rainbow ? RainbowPalette.color(position:x) : color
            return (key.id, RGB(r: UInt8(Double(tint.r)*intensity), g: UInt8(Double(tint.g)*intensity), b: UInt8(Double(tint.b)*intensity)))
        })
    }
}

struct AudioReactor {
    private var baseline = 0.0
    private var peak = 0.2
    private var output = 0.0
    mutating func update(_ input: Double, sensitivity: Double = 1, interval:Double = 1.0/30) -> Double {
        let raw = input.isFinite ? min(1,max(0,input)) : 0
        let response = sensitivity.isFinite ? min(2,max(0.5,sensitivity)) : 1
        let steps = min(6,max(0.1,interval.isFinite ? interval*30 : 1))
        baseline += (raw-baseline)*(1-pow(1-0.065,steps))
        peak = max(raw,peak*pow(0.985,steps))
        // Sensitivity changes the onset threshold and timing, not the bar's
        // maximum height. A steady loud passage leaves room for the next beat.
        let threshold = 0.06/response
        let excursion = min(1,max(0,(raw-baseline-threshold)/(max(0.16,peak-baseline)+threshold)))
        let target = min(1,pow(raw,2.2)*0.18+pow(excursion,0.72)*0.9)
        let coefficient = target > output ? 0.55+response*0.13 : 0.18+response*0.06
        output += (target-output)*(1-pow(1-coefficient,steps))
        return output
    }
}

struct AudioSpectrumReactor {
    private var reactors = [AudioReactor](repeating:AudioReactor(),count:AudioSpectrumAnalyzer.bandCount)
    mutating func update(_ input:[Double],sensitivity:Double,interval:Double = 1.0/30) -> [Double] {
        reactors.indices.map { index in reactors[index].update(index < input.count ? input[index] : 0,sensitivity:sensitivity,interval:interval) }
    }
}

// Bounded, real PCM analysis. No synthetic animation or audio file is needed.
// A Hann-windowed radix-2 FFT feeds 24 logarithmic bands from 55 Hz to 16 kHz.
struct AudioSpectrumAnalyzer {
    static let bandCount = 24
    static let sampleCount = 2048
    private var samples = [Double]()
    private static let window = (0..<sampleCount).map { 0.5-0.5*cos(2*Double.pi*Double($0)/Double(sampleCount-1)) }
    mutating func append(_ values:[Double]) {
        samples.append(contentsOf:values.suffix(Self.sampleCount).map { $0.isFinite ? min(1,max(-1,$0)) : 0 })
        if samples.count > Self.sampleCount { samples.removeFirst(samples.count-Self.sampleCount) }
    }
    func bands(sampleRate:Double) -> [Double] {
        let silent = [Double](repeating:0,count:Self.bandCount)
        guard samples.count == Self.sampleCount, sampleRate.isFinite, (8000...192000).contains(sampleRate) else { return silent }
        let n = Self.sampleCount
        let mean = samples.reduce(0,+)/Double(n)
        var real = zip(samples,Self.window).map { ($0.0-mean)*$0.1 }
        var imaginary = [Double](repeating:0,count:n)
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { real.swapAt(i,j) }
        }
        var length = 2
        while length <= n {
            let angle = -2*Double.pi/Double(length)
            let rootR = cos(angle), rootI = sin(angle)
            for start in stride(from:0,to:n,by:length) {
                var wr = 1.0, wi = 0.0
                for offset in 0..<(length/2) {
                    let a = start+offset, b = a+length/2
                    let tr = wr*real[b]-wi*imaginary[b], ti = wr*imaginary[b]+wi*real[b]
                    real[b] = real[a]-tr; imaginary[b] = imaginary[a]-ti
                    real[a] += tr; imaginary[a] += ti
                    let nextR = wr*rootR-wi*rootI
                    wi = wr*rootI+wi*rootR; wr = nextR
                }
            }
            length <<= 1
        }
        let upper = min(16000,sampleRate*0.46)
        let normalization = 2/Self.window.reduce(0,+)
        return (0..<Self.bandCount).map { band in
            let low = 55*pow(upper/55,Double(band)/Double(Self.bandCount))
            let high = 55*pow(upper/55,Double(band+1)/Double(Self.bandCount))
            let first = max(1,min(n/2-1,Int((low*Double(n)/sampleRate).rounded())))
            let end = max(first+1,min(n/2,Int((high*Double(n)/sampleRate).rounded())))
            let amplitude = (first..<end).map { hypot(real[$0],imaginary[$0])*normalization }.max() ?? 0
            guard amplitude > 0.0003 else { return 0 }
            return min(1,max(0,(20*log10(amplitude)+70)/60))
        }
    }
}

enum BannerDeduplicator {
    static func newIDs(previous: Set<String>?, current: Set<String>) -> Set<String> {
        guard let previous else { return [] } // Existing banners at opt-in are not new events.
        return current.subtracting(previous)
    }
}
