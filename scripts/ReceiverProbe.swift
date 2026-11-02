// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.hid
import CryptoKit

@main enum ReceiverProbe {
    static func main() throws {
        let arguments = Set(CommandLine.arguments.dropFirst())
        guard arguments.isSubset(of:["--read-feature06"]) else {
            FileHandle.standardError.write(Data("用法：scripts/probe-receiver.sh [--read-feature06]\n".utf8)); exit(2)
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault,0)
        IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:0x25a7,kIOHIDProductIDKey:0xfa70] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var metadata = [[String:Any]](), candidates = [IOHIDDevice]()
        for device in devices {
            func number(_ key:String)->Int { IOHIDDeviceGetProperty(device,key as CFString) as? Int ?? 0 }
            let descriptor = IOHIDDeviceGetProperty(device,kIOHIDReportDescriptorKey as CFString) as? Data ?? Data()
            let identity = DeviceDescriptor(vendorID:number(kIOHIDVendorIDKey),productID:number(kIOHIDProductIDKey),product:"2.4G Wireless Receiver",transport:IOHIDDeviceGetProperty(device,kIOHIDTransportKey as CFString) as? String ?? "",usagePage:number(kIOHIDPrimaryUsagePageKey),usage:number(kIOHIDPrimaryUsageKey),featureBytes:number(kIOHIDMaxFeatureReportSizeKey))
            let version = number(kIOHIDVersionNumberKey)
            let eligible = ReceiverResearch.permitsStatusRead(device:identity,version:version,descriptor:descriptor)
            metadata.append(["identifier":identity.identifier,"version":String(format:"%04X",version),"transport":identity.transport,"usagePage":identity.usagePage,"usage":identity.usage,"featureBytes":identity.featureBytes,"outputBytes":number(kIOHIDMaxOutputReportSizeKey),"descriptorSHA256":SHA256.hash(data:descriptor).map { String(format:"%02x",$0) }.joined(),"statusReadEligible":eligible])
            if eligible { candidates.append(device) }
        }
        var result:[String:Any] = ["schemaVersion":1,"operation":arguments.isEmpty ? "property-enumeration-only" : "GET_FEATURE 06 only","interfaces":metadata,"lightingSupported":false,"settingsWrites":0,"inputCallbacksRegistered":false]
        if !arguments.isEmpty {
            if candidates.count == 1, let device = candidates.first {
                let opened = IOHIDDeviceOpen(device,0)
                result["openResult"] = String(format:"0x%08x",opened)
                if opened == kIOReturnSuccess {
                    defer { IOHIDDeviceClose(device,0) }
                    var reads = [[String:Any]]()
                    for _ in 0..<3 {
                        var bytes = [UInt8](repeating:0,count:8); bytes[0] = 6; var length = bytes.count
                        let status = bytes.withUnsafeMutableBufferPointer { IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,6,$0.baseAddress!,&length) }
                        let valid = status == kIOReturnSuccess && length == 8 && bytes[0] == 6
                        var row:[String:Any] = ["result":String(format:"0x%08x",status),"length":length,"validEnvelope":valid]
                        // Unknown payload may contain pairing identifiers. Keep
                        // it local; default output contains only equality hashes.
                        if valid { row["payloadSHA256"] = SHA256.hash(data:Data(bytes)).map { String(format:"%02x",$0) }.joined() }
                        reads.append(row)
                        if !valid { break }
                        Thread.sleep(forTimeInterval:0.05)
                    }
                    result["reads"] = reads
                }
            } else { result["error"] = "需要唯一匹配 0391 版本与已核对描述符的接收器；没有打开设备。" }
        }
        let data = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
}
