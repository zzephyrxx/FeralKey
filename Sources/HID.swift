// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.hid

protocol KeyboardTransport: AnyObject {
    var connected: Bool { get }
    var writesAuthorized: Bool { get set }
    func scan() -> [[String: Any]]
    func open() throws
    func close()
    func send(_ reports: [[UInt8]]) throws
    func beginColorStream()
    func endColorStream()
    func sendLive(_ reports:[[UInt8]], completion:@escaping (Result<Void,Error>)->Void)
}
extension KeyboardTransport {
    func beginColorStream() {}
    func endColorStream() {}
    func sendLive(_ reports:[[UInt8]],completion:@escaping (Result<Void,Error>)->Void) { completion(Result { try send(reports) }) }
}

final class KeyboardHID: KeyboardTransport {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var planner = HIDWritePlanner()
    private var streaming = false
    private let ioLock = NSRecursiveLock()
    private let liveQueue = DispatchQueue(label:"feralkey.hid-live",qos:.userInitiated)
    private var streamEpoch: UInt64 = 0
    var writesAuthorized = false
    var connected: Bool { ioLock.lock(); defer { ioLock.unlock() }; return device != nil }
    deinit { close() }

    func scan() -> [[String: Any]] {
        ioLock.lock(); defer { ioLock.unlock() }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(m, [
            [kIOHIDVendorIDKey:0x258a,kIOHIDProductIDKey:0x00c1],
            [kIOHIDVendorIDKey:0x25a7,kIOHIDProductIDKey:0xfa70]
        ] as CFArray)
        manager = m
        return ((IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? []).map { d in
            var info: [String: Any] = [:]
            for key in [kIOHIDVendorIDKey, kIOHIDProductIDKey, kIOHIDProductKey, kIOHIDTransportKey, kIOHIDPrimaryUsageKey, kIOHIDPrimaryUsagePageKey, kIOHIDMaxFeatureReportSizeKey] {
                info[key] = IOHIDDeviceGetProperty(d, key as CFString)
            }
            return info
        }
    }

    func open() throws {
        ioLock.lock(); defer { ioLock.unlock() }
        close()
        _ = scan()
        guard let m = manager,
              let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { throw RKError.message("没有找到键盘设备。") }
        let matches = devices.filter {
                  (IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? Int) == 0x258a &&
                  (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int) == 0x00c1 &&
                  (IOHIDDeviceGetProperty($0, kIOHIDPrimaryUsageKey as CFString) as? Int) == 128 &&
                  (IOHIDDeviceGetProperty($0, kIOHIDPrimaryUsagePageKey as CFString) as? Int) == 1 &&
                  (IOHIDDeviceGetProperty($0, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int) == 65 &&
                  (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String) == "USB"
        }
        if matches.isEmpty && devices.contains(where:{
            (IOHIDDeviceGetProperty($0,kIOHIDVendorIDKey as CFString) as? Int) == 0x25a7 &&
            (IOHIDDeviceGetProperty($0,kIOHIDProductIDKey as CFString) as? Int) == 0xfa70
        }) { throw RKError.message(ReceiverResearch.unavailable) }
        guard matches.count == 1, let d = matches.first else { throw RKError.message(matches.isEmpty ? "没有找到 258A:00C1 的 USB 控制接口。请确认连接线与有线模式。" : "发现多个相同控制接口。请只连接一把待测试的 RK98，再重新连接。") }
        let result = IOHIDDeviceOpen(d, 0)
        guard result == kIOReturnSuccess else {
            throw RKError.message(String(format: "macOS 拒绝打开设备（0x%08x）。请在「系统设置 → 隐私与安全性 → 输入监控」添加 FeralKey.app，允许后退出并重新打开本工具。", result))
        }
        device = d
    }

    func close() {
        ioLock.lock(); defer { ioLock.unlock() }
        streamEpoch &+= 1
        if let d = device { IOHIDDeviceClose(d, 0) }
        device = nil
        manager = nil
        planner.reset()
        streaming = false
    }
    func beginColorStream() { ioLock.lock(); defer { ioLock.unlock() }; streamEpoch &+= 1; streaming = true }
    func endColorStream() { ioLock.lock(); defer { ioLock.unlock() }; streamEpoch &+= 1; streaming = false; planner.reset() }
    func sendLive(_ reports:[[UInt8]],completion:@escaping (Result<Void,Error>)->Void) {
        ioLock.lock(); let epoch = streamEpoch; ioLock.unlock()
        liveQueue.async { [weak self] in
            let result: Result<Void,Error> = Result {
                guard let self else { throw RKError.message("设备已关闭") }
                self.ioLock.lock(); defer { self.ioLock.unlock() }
                guard epoch == self.streamEpoch else { throw RKError.message("旧灯光帧已取消") }
                try self.send(reports)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func send(_ reports: [[UInt8]]) throws {
        ioLock.lock(); defer { ioLock.unlock() }
        guard writesAuthorized else { throw RKError.message("请先阅读并接受实验功能风险须知。") }
        let live = reports.count == 7
        let packets: [[UInt8]]
        if live {
            guard streaming else { throw RKError.message("实时颜色通道尚未启用") }
            try RKCodec.validateLiveColors(reports); packets = reports
        } else {
            _ = try planner.packets(for:reports); packets = reports
        }
        guard let d = device else { throw RKError.message("请先连接键盘控制接口") }
        for (index,bytes) in packets.enumerated() {
            if live && index > 0 { Thread.sleep(forTimeInterval:0.001) }
            // Entire allowlisted transaction was validated before its first write.
            let result = bytes.withUnsafeBufferPointer { ptr in
                IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 10, ptr.baseAddress!, ptr.count)
            }
            guard result == kIOReturnSuccess else {
                close()
                throw RKError.message(String(format:"发送未完成（0x%08x）。已停止发送，请重新连接；配置可能只完成一部分，请观察实物后再决定是否重新应用。",result))
            }
        }
        if !live { planner.didSend(reports) }
    }
}
