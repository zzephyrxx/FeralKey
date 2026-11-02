// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main enum BluetoothResearchTests {
    static func main() {
        var checks = 0
        func check(_ value:Bool,_ message:String) { precondition(value,message); checks += 1 }
        check(BluetoothResearch.matchesName("RK98RGB 5.0 "),"actual trailing space accepted")
        check(BluetoothResearch.matchesName(" rk98rgb 5.0\n"),"case and whitespace normalized")
        for name:String? in [nil,"RK98","RK98RGB 5.0 other","RK98RGB 5.0\0","RK84"] {
            check(!BluetoothResearch.matchesName(name),"other devices rejected")
        }
        for (service,characteristic) in [("180A","2A29"),("180F","2A19"),("1812","2A4B"),("180a","2a50")] {
            check(BluetoothResearch.allowsValueRead(service:service,characteristic:characteristic),"standard metadata allowed")
        }
        for (service,characteristic) in [("180A","2A25"),("1812","2A4D"),("1812","2A22"),("1812","2A4C"),("1812","2A4E"),("180F","2A29"),("FFF0","FFF1"),("FFF0","2A19")] {
            check(!BluetoothResearch.allowsValueRead(service:service,characteristic:characteristic),"serial, input, control and vendor reads rejected")
        }
        for percent in [0,42,100] {
            check(BluetoothResearch.safeValue(service:"180F",characteristic:"2A19",data:Data([UInt8(percent)]))?["batteryPercent"] as? Int == percent,"valid battery decoded")
        }
        for bytes:[UInt8] in [[],[101],[255],[50,0]] {
            check(BluetoothResearch.safeValue(service:"180F",characteristic:"2A19",data:Data(bytes)) == nil,"malformed battery rejected")
        }
        check(BluetoothResearch.safeValue(service:"180A",characteristic:"2A29",data:Data("BE\nKEN\0".utf8))?["text"] as? String == "BEKEN","controls removed")
        check(BluetoothResearch.safeValue(service:"180A",characteristic:"2A28",data:Data([0xff])) == nil,"invalid UTF8 rejected")
        check(BluetoothResearch.safeValue(service:"180A",characteristic:"2A29",data:Data(repeating:65,count:129)) == nil,"oversized strings rejected")
        check((BluetoothResearch.safeValue(service:"180A",characteristic:"2A29",data:Data(repeating:65,count:100))?["text"] as? String)?.count == 80,"strings bounded")
        check(BluetoothResearch.safeValue(service:"1812",characteristic:"2A4B",data:Data(repeating:0,count:4097)) == nil,"oversized metadata rejected")
        check(BluetoothResearch.safeValue(service:"1812",characteristic:"2A4D",data:Data([1,2])) == nil,"input values cannot be exported")
        check(BluetoothResearch.safeValue(service:"180A",characteristic:"2A25",data:Data("serial".utf8)) == nil,"serial cannot be exported")
        check(BluetoothResearch.safeValue(service:"180A",characteristic:"2A50",data:Data([2,14,0,18,52,1,103]))?["hex"] as? String == "020e0012340167","PnP bytes preserved")
        print("\(checks) Bluetooth read policy checks passed; no Bluetooth connection or device writes.")
    }
}
