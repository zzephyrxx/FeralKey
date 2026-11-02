// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.hid
import CryptoKit

enum ResearchNotice {
    static let version = 1
    static let text = """
    本功能用于研究、学习及兼容性探索。请仅对您拥有或已获得明确授权的设备进行操作，并遵守适用法律法规，不得用于任何违法活动或侵犯他人合法权益。

    不同品牌、型号及硬件版本可能采用不同协议。本项目不保证所有设备均可识别、适配或恢复。探索及测试操作可能导致配置丢失、功能异常、设备无法使用，甚至永久损坏。

    建议使用闲置、备用或可接受损坏的键盘，避免使用日常工作依赖的唯一设备。操作前请阅读说明，并在具备条件时备份原有配置。本版本无法备份键盘内部配置。

    本项目按现状提供，不对设备兼容性、操作结果或恢复能力作出保证。在适用法律允许的范围内，作者及贡献者不对因使用本项目产生的设备损坏、数据丢失或其他损失承担责任。

    勾选并继续，表示您已阅读、理解上述风险，并自愿承担相应操作风险。
    """
}

struct DeviceDescriptor: Codable, Identifiable, Equatable {
    let vendorID: Int
    let productID: Int
    let product: String
    let transport: String
    let usagePage: Int
    let usage: Int
    let featureBytes: Int
    var id: String { "\(vendorID):\(productID):\(transport):\(usagePage):\(usage):\(featureBytes)" }
    var identifier: String { String(format: "%04X:%04X", vendorID, productID) }
    var matchesRK98Control: Bool { vendorID == 0x258a && productID == 0xc1 && transport == "USB" && usagePage == 1 && usage == 128 && featureBytes == 65 }
    // Shared Compx identity: recognition is not an RK model or RGB match.
    var isCompxReceiver: Bool { vendorID == 0x25a7 && productID == 0xfa70 && transport == "USB" }
}

enum ReceiverResearch {
    static let unavailable = "已识别 2.4G 接收器 25A7:FA70；尚未找到这版接收器的灯光控制协议。有线 RGB 报文不会发送到接收器。"
    static let descriptorSHA256 = "96a6726819c30cb0c4448d629806eba90fd225c3e04f6f9182e789a2aaee6382"
    static func permitsStatusRead(device:DeviceDescriptor,version:Int,descriptor:Data) -> Bool {
        device.isCompxReceiver && device.usagePage == 1 && device.usage == 2 && device.featureBytes == 8 && version == 0x0391 &&
        SHA256.hash(data:descriptor).map { String(format:"%02x",$0) }.joined() == descriptorSHA256
    }
}

enum DeviceDiscovery {
    // Property enumeration only: no device open, input callbacks or reports.
    static func scan() -> [DeviceDescriptor] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, nil)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let descriptors = devices.map { d -> DeviceDescriptor in
            func int(_ key: String) -> Int { IOHIDDeviceGetProperty(d, key as CFString) as? Int ?? 0 }
            func string(_ key: String) -> String { IOHIDDeviceGetProperty(d, key as CFString) as? String ?? "未知" }
            return DeviceDescriptor(vendorID: int(kIOHIDVendorIDKey), productID: int(kIOHIDProductIDKey), product: string(kIOHIDProductKey), transport: string(kIOHIDTransportKey), usagePage: int(kIOHIDPrimaryUsagePageKey), usage: int(kIOHIDPrimaryUsageKey), featureBytes: int(kIOHIDMaxFeatureReportSizeKey))
        }
        let keyboardPairs = Set(descriptors.filter { $0.usagePage == 1 && $0.usage == 6 }.map { "\($0.vendorID):\($0.productID)" })
        var unique: [String: DeviceDescriptor] = [:]
        for d in descriptors where keyboardPairs.contains("\(d.vendorID):\(d.productID)") || d.matchesRK98Control || d.isCompxReceiver { unique[d.id] = d }
        return unique.values.sorted { $0.id < $1.id }
    }
    static func researchPackage(devices: [DeviceDescriptor]) throws -> Data {
        struct Package: Encodable {
            let schemaVersion = 1
            let appVersion = "0.10.0"
            let platform = "macOS"
            let contains = "接口元数据；不包含序列号、账号、额度、输入内容或设备配置备份"
            let verification = "property-enumeration-only; hardware-effects-unverified"
            let devices: [DeviceDescriptor]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Package(devices: devices))
    }
}
