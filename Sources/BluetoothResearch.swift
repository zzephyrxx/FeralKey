// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum BluetoothResearch {
    static func matchesName(_ name:String?) -> Bool {
        name?.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() == "RK98RGB 5.0"
    }
    static func allowsValueRead(service:String,characteristic:String) -> Bool {
        let allowed:[String:Set<String>] = [
            "1800":["2A00","2A01"],
            "180A":["2A24","2A26","2A27","2A28","2A29","2A50"],
            "180F":["2A19"],
            "1812":["2A4A","2A4B"]
        ]
        return allowed[service.uppercased()]?.contains(characteristic.uppercased()) == true
    }
    static func safeValue(service:String,characteristic:String,data:Data) -> [String:Any]? {
        guard allowsValueRead(service:service,characteristic:characteristic), data.count <= 4096 else { return nil }
        if service.uppercased() == "180F" && characteristic.uppercased() == "2A19" {
            guard data.count == 1, let percentage = data.first, percentage <= 100 else { return nil }
            return ["batteryPercent":Int(percentage)]
        }
        if ["2A00","2A24","2A26","2A27","2A28","2A29"].contains(characteristic.uppercased()) {
            guard data.count <= 128, let string = String(data:data,encoding:.utf8) else { return nil }
            return ["text":String(string.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80))]
        }
        return ["bytes":data.count,"hex":data.map { String(format:"%02x",$0) }.joined()]
    }
}
