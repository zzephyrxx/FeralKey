// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreBluetooth

final class BluetoothProbe:NSObject,CBCentralManagerDelegate,CBPeripheralDelegate {
    private var central:CBCentralManager!
    private var target:CBPeripheral?
    private var candidates = [UUID:CBPeripheral]()
    private var started = false
    private var finished = false
    private var pending = 0
    private var valueReads = Set<ObjectIdentifier>()
    private var descriptorReads = Set<ObjectIdentifier>()
    private let output:URL
    private var result:[String:Any] = ["schemaVersion":1,"target":"RK98RGB 5.0","operation":"GATT discovery and allowlisted standard reads only","settingsWrites":0,"notificationSubscriptions":0,"inputReportsRead":0,"lightingSupported":"unverified"]
    private var services = [[String:Any]]()
    private var characteristics = [[String:Any]]()
    private var descriptors = [[String:Any]]()
    private var values = [[String:Any]]()
    private var failures = [[String:Any]]()
    init(output:URL) { self.output = output; super.init() }
    func start() {
        publish("starting")
        central = CBCentralManager(delegate:self,queue:.main,options:[CBCentralManagerOptionShowPowerAlertKey:false])
        DispatchQueue.main.asyncAfter(deadline:.now()+90) { [weak self] in self?.finish("deadline_reached") }
    }
    private func publish(_ state:String) {
        result["state"] = state; result["services"] = services; result["characteristics"] = characteristics
        result["descriptors"] = descriptors; result["standardValues"] = values; result["errors"] = failures
        result["bluetoothAuthorization"] = CBManager.authorization.rawValue
        do { try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic) }
        catch { FileHandle.standardError.write(Data("无法保存蓝牙诊断结果\n".utf8)); exit(2) }
    }
    private func record(_ operation:String,_ error:Error) {
        let e = error as NSError
        failures.append(["operation":operation,"domain":e.domain,"code":e.code])
    }
    func centralManagerDidUpdateState(_ central:CBCentralManager) {
        guard !finished else { return }
        result["centralState"] = central.state.rawValue
        guard CBManager.authorization != .denied && CBManager.authorization != .restricted else { finish("bluetooth_permission_required"); return }
        guard central.state == .poweredOn else { publish(CBManager.authorization == .notDetermined ? "awaiting_bluetooth_permission" : "bluetooth_not_ready"); return }
        guard !started else { return }; started = true
        for p in central.retrieveConnectedPeripherals(withServices:[CBUUID(string:"1812"),CBUUID(string:"180F"),CBUUID(string:"180A")]) where BluetoothResearch.matchesName(p.name) { candidates[p.identifier] = p }
        central.scanForPeripherals(withServices:nil,options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
        publish("finding_connected_keyboard")
        DispatchQueue.main.asyncAfter(deadline:.now()+8) { [weak self] in self?.selectTarget() }
    }
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) {
        guard !finished, target == nil else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if BluetoothResearch.matchesName(name) { candidates[peripheral.identifier] = peripheral }
    }
    private func selectTarget() {
        guard !finished else { return }; central.stopScan()
        result["matchingTargetCount"] = candidates.count
        guard candidates.count == 1, let p = candidates.values.first else { finish(candidates.isEmpty ? "keyboard_not_visible_to_corebluetooth" : "multiple_matching_keyboards"); return }
        target = p; p.delegate = self
        publish("connecting_diagnostic_client")
        central.connect(p,options:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+20) { [weak self] in self?.finish("discovery_deadline_reached") }
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) {
        guard !finished, peripheral === target else { return }
        pending = 1; publish("discovering_services"); peripheral.discoverServices(nil)
    }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) {
        guard peripheral === target else { return }; if let error { record("connect",error) }; finish("connection_failed")
    }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        guard !finished, peripheral === target else { return }; if let error { record("connection",error) }; finish("diagnostic_connection_ended")
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard !finished, peripheral === target else { return }; pending -= 1
        if let error { record("discoverServices",error) }
        let found = peripheral.services ?? []
        guard found.count <= 64 else { finish("service_limit_exceeded"); return }
        for service in found {
            services.append(["uuid":service.uuid.uuidString,"primary":service.isPrimary])
            pending += 1; peripheral.discoverCharacteristics(nil,for:service)
        }
        completeIfReady()
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        guard !finished, peripheral === target else { return }; pending -= 1
        if let error { record("discoverCharacteristics "+service.uuid.uuidString,error) }
        let found = service.characteristics ?? []
        guard found.count <= 128, characteristics.count+found.count <= 512 else { finish("characteristic_limit_exceeded"); return }
        for c in found {
            let s = service.uuid.uuidString, id = c.uuid.uuidString
            characteristics.append(["service":s,"uuid":id,"properties":c.properties.rawValue,"read":c.properties.contains(.read),"write":c.properties.contains(.write),"writeWithoutResponse":c.properties.contains(.writeWithoutResponse),"notify":c.properties.contains(.notify),"indicate":c.properties.contains(.indicate)])
            if c.properties.contains(.read), BluetoothResearch.allowsValueRead(service:s,characteristic:id) { pending += 1; valueReads.insert(ObjectIdentifier(c)); peripheral.readValue(for:c) }
            if s == "1812", id == "2A4D" { pending += 1; peripheral.discoverDescriptors(for:c) }
        }
        completeIfReady()
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard !finished, peripheral === target else { return }
        let service = characteristic.service?.uuid.uuidString ?? "", id = characteristic.uuid.uuidString
        guard BluetoothResearch.allowsValueRead(service:service,characteristic:id), valueReads.remove(ObjectIdentifier(characteristic)) != nil else { return }
        pending -= 1
        if let error { record("read "+service+"/"+id,error) }
        else if let data = characteristic.value, let value = BluetoothResearch.safeValue(service:service,characteristic:id,data:data) { values.append(["service":service,"uuid":id,"value":value]) }
        completeIfReady()
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverDescriptorsFor characteristic:CBCharacteristic,error:Error?) {
        guard !finished, peripheral === target else { return }; pending -= 1
        if let error { record("discoverDescriptors",error) }
        guard (characteristic.descriptors?.count ?? 0) <= 64 else { finish("descriptor_limit_exceeded"); return }
        for d in characteristic.descriptors ?? [] {
            descriptors.append(["service":"1812","characteristic":characteristic.uuid.uuidString,"uuid":d.uuid.uuidString])
            if d.uuid.uuidString == "2908" { pending += 1; descriptorReads.insert(ObjectIdentifier(d)); peripheral.readValue(for:d) }
        }
        completeIfReady()
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor descriptor:CBDescriptor,error:Error?) {
        guard !finished, peripheral === target, descriptor.uuid.uuidString == "2908", descriptorReads.remove(ObjectIdentifier(descriptor)) != nil else { return }; pending -= 1
        if let error { record("readReportReference",error) }
        else if let data = descriptor.value as? Data, data.count == 2 { values.append(["service":"1812","uuid":"2908","reportID":Int(data[0]),"reportType":Int(data[1])]) }
        completeIfReady()
    }
    private func completeIfReady() { publish("discovering_services"); if pending == 0 { finish(failures.isEmpty ? "discovery_completed" : "discovery_completed_with_errors") } }
    private func finish(_ state:String) {
        guard !finished else { return }; finished = true; central?.stopScan(); publish(state)
        // Release only this client's connection. Do not remove pairing or
        // request a system keyboard disconnect.
        if let target { central?.cancelPeripheralConnection(target) }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { exit(0) }
    }
}

@main enum BluetoothProbeMain {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3, args[1] == "--output", args[2].hasPrefix("/") else { exit(2) }
        let probe = BluetoothProbe(output:URL(fileURLWithPath:args[2]))
        probe.start(); withExtendedLifetime(probe) { RunLoop.main.run() }
    }
}
