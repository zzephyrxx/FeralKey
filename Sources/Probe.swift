import Foundation
import IOKit.hid
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey:0x258a,kIOHIDProductIDKey:0x00c1] as CFDictionary)
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
var results: [[String:Any]] = []
for device in devices {
    var info: [String:Any] = [:]
    for key in [kIOHIDVendorIDKey,kIOHIDProductIDKey,kIOHIDProductKey,kIOHIDTransportKey,kIOHIDPrimaryUsageKey,kIOHIDPrimaryUsagePageKey,kIOHIDMaxFeatureReportSizeKey,kIOHIDMaxOutputReportSizeKey] {
        info[key] = IOHIDDeviceGetProperty(device,key as CFString)
    }
    if let descriptor = IOHIDDeviceGetProperty(device,kIOHIDReportDescriptorKey as CFString) as? Data {
        info["descriptorHex"] = descriptor.map{String(format:"%02x",$0)}.joined()
    }
    if (info[kIOHIDMaxFeatureReportSizeKey] as? Int ?? 0) >= 65 {
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        info["openStatus"] = String(format:"0x%08x",status)
        if status == kIOReturnSuccess {
            var bytes = [UInt8](repeating:0,count:65); bytes[0] = 0x0a
            var length = bytes.count
            let get = IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,10,&bytes,&length)
            info["getStatus"] = String(format:"0x%08x",get)
            info["length"] = length
            if get == kIOReturnSuccess { info["featureHex"] = bytes.prefix(length).map{String(format:"%02x",$0)}.joined() }
            IOHIDDeviceClose(device,0)
        }
    }
    results.append(info)
}
let data = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
print(String(data:data,encoding:.utf8)!)
