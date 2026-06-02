import Foundation
import CoreBluetooth

class MeshManager: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    static let shared = MeshManager()
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let profileCharUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private var localDeviceId: String = ""
    private var localProfileJson: String = ""
    private var isRunning = false
    
    // Core BLE Components
    private var profileCharacteristic: CBMutableCharacteristic?
    
    // Helpers
    private let peerRegistry = BlePeerRegistry()
    private let dedupCache = DeduplicationCache()
    private var relayController: RelayController?
    
    // Callbacks to Flutter
    var onPeerDiscovered: ((String) -> Void)?
    var onPacketReceived: ((String) -> Void)?
    
    private override init() {
        super.init()
    }
    
    func startMesh(profileJson: String) {
        if isRunning { return }
        
        guard let data = profileJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let deviceId = dict["deviceId"] as? String else { return }
              
        self.localDeviceId = deviceId
        self.localProfileJson = profileJson
        
        relayController = RelayController(localDeviceId: localDeviceId, deduplicationCache: dedupCache) { [weak self] packet in
            self?.relayPacket(packet: packet)
        }
        
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "liita-central"]
        )
        
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "liita-peripheral"]
        )
        
        isRunning = true
    }
    
    func stopMesh() {
        if !isRunning { return }
        
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        
        peerRegistry.clear()
        dedupCache.clear()
        
        isRunning = false
    }
    
    // MARK: - Outbound Relaying
    
    func sendPacketFromDart(jsonStr: String) {
        guard let packet = MeshPacket.fromJson(jsonStr) else { return }
        
        // Add to our own dedup cache so we don't echo it
        _ = dedupCache.recordAndGetDegree(packetId: packet.packetId)
        
        relayPacket(packet: packet)
    }
    
    private func relayPacket(packet: MeshPacket) {
        guard let jsonStr = packet.toJsonString(),
              let base64Str = Utils.compressAndEncode(jsonStr),
              let payloadData = base64Str.data(using: .utf8) else { return }
        
        let connections = peerRegistry.getAllConnections()
        for peripheral in connections {
            // Find the characteristic
            guard let service = peripheral.services?.first(where: { $0.uuid == MeshManager.serviceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid == MeshManager.profileCharUUID }) else {
                continue
            }
            peripheral.writeValue(payloadData, for: characteristic, type: .withoutResponse)
        }
    }
    
    // MARK: - Central Manager
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isRunning {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                peripheral.delegate = self
                peerRegistry.addConnection(peripheral)
            }
        }
    }
    
    private func startScanning() {
        centralManager?.scanForPeripherals(
            withServices: [MeshManager.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // CoreBluetooth handles duplicates if AllowDuplicates is false
        // Connect to it to read its profile and become ready to write MeshPackets
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peerRegistry.addConnection(peripheral)
        peripheral.discoverServices([MeshManager.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peerRegistry.removeConnection(peripheral.identifier.uuidString)
        // Auto-reconnect
        if isRunning {
            centralManager?.connect(peripheral, options: nil)
        }
    }
    
    // MARK: - CBPeripheralDelegate (Client Side)
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == MeshManager.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([MeshManager.profileCharUUID], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let char = service.characteristics?.first(where: { $0.uuid == MeshManager.profileCharUUID }) else { return }
        // Read full profile since iOS doesn't give us scan response data
        peripheral.readValue(for: char)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == MeshManager.profileCharUUID {
            if let data = characteristic.value, let profileJson = String(data: data, encoding: .utf8) {
                // If it's a valid profile JSON
                if profileJson.contains("deviceId") {
                    if peerRegistry.updatePeerProfile(deviceId: peripheral.identifier.uuidString, profileJson: profileJson) {
                        onPeerDiscovered?(profileJson)
                    }
                }
            }
        }
    }
    
    // MARK: - Peripheral Manager (Advertising & GATT Server)
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && isRunning {
            startAdvertising()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // State restoration
    }
    
    private func startAdvertising() {
        guard let peripheralManager = peripheralManager else { return }
        
        let service = CBMutableService(type: MeshManager.serviceUUID, primary: true)
        
        profileCharacteristic = CBMutableCharacteristic(
            type: MeshManager.profileCharUUID,
            properties: [.read, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        service.characteristics = [profileCharacteristic!]
        peripheralManager.add(service)
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [MeshManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: localDeviceId.prefix(8)
        ]
        
        peripheralManager.startAdvertising(advertisementData)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == MeshManager.profileCharUUID {
            let profileData = localProfileJson.data(using: .utf8) ?? Data()
            
            if request.offset > profileData.count {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            
            request.value = profileData.subdata(in: request.offset..<profileData.count)
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == MeshManager.profileCharUUID {
                if let data = request.value {
                    handleIncomingGattWrite(data)
                }
                peripheral.respond(to: request, withResult: .success)
            }
        }
    }
    
    private func handleIncomingGattWrite(_ data: Data) {
        guard let base64Str = String(data: data, encoding: .utf8),
              let jsonStr = Utils.decodeAndDecompress(base64Str),
              let packet = MeshPacket.fromJson(jsonStr) else { return }
              
        let degree = dedupCache.recordAndGetDegree(packetId: packet.packetId)
        if degree > 1 { return } // Duplicate
        
        if packet.destinationId == localDeviceId || packet.isBroadcast {
            onPacketReceived?(jsonStr)
        }
        
        relayController?.processForRelay(packet: packet)
    }
    
    // MARK: - Duty Cycling API (Stubs for iOS as CoreBluetooth handles background scanning intervals automatically)
    
    func setForegroundMode() {}
    func setBackgroundMode() {}
    func setContinuousMode() {}
}
