// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.hid

// Metadata only: do not open the HID device or register input callbacks.
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey:0x000e,kIOHIDProductIDKey:0x3412] as CFDictionary)
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
var rows = [[String:Any]]()
for device in devices {
    let transport = IOHIDDeviceGetProperty(device,kIOHIDTransportKey as CFString) as? String ?? ""
    let name = IOHIDDeviceGetProperty(device,kIOHIDProductKey as CFString) as? String
    guard transport == "Bluetooth Low Energy", BluetoothResearch.matchesName(name) else { continue }
    var row = [String:Any]()
    for key in [kIOHIDVendorIDKey,kIOHIDProductIDKey,kIOHIDVersionNumberKey,kIOHIDProductKey,kIOHIDManufacturerKey,kIOHIDTransportKey,kIOHIDPrimaryUsagePageKey,kIOHIDPrimaryUsageKey,kIOHIDMaxInputReportSizeKey,kIOHIDMaxOutputReportSizeKey,kIOHIDMaxFeatureReportSizeKey,kIOHIDDeviceUsagePairsKey] {
        if let value = IOHIDDeviceGetProperty(device,key as CFString) { row[key] = value }
    }
    if let data = IOHIDDeviceGetProperty(device,kIOHIDReportDescriptorKey as CFString) as? Data, data.count <= 4096 {
        row["reportDescriptorHex"] = data.map { String(format:"%02x",$0) }.joined()
    }
    rows.append(row)
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]))
