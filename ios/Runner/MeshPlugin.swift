import Flutter
import UIKit

public class MeshPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var peersSink: FlutterEventSink?
    private var packetsSink: FlutterEventSink?
    
    // We differentiate handlers by keeping a reference to this instance,
    // but StreamHandler requires distinct instances for each channel if they have different logic.
    // For simplicity, we'll create two internal classes for the streams.
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "com.liita.app/mesh",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = MeshPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        let peersChannel = FlutterEventChannel(name: "com.liita.app/peers", binaryMessenger: registrar.messenger())
        let peersHandler = PeersStreamHandler()
        peersChannel.setStreamHandler(peersHandler)
        
        let packetsChannel = FlutterEventChannel(name: "com.liita.app/packets", binaryMessenger: registrar.messenger())
        let packetsHandler = PacketsStreamHandler()
        packetsChannel.setStreamHandler(packetsHandler)
        
        MeshManager.shared.onPeerDiscovered = { profileJson in
            peersHandler.sink?(profileJson)
        }
        
        MeshManager.shared.onPacketReceived = { packetJson in
            packetsHandler.sink?(packetJson)
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startMesh":
            if let args = call.arguments as? [String: Any],
               let profileJson = args["profileJson"] as? String {
                MeshManager.shared.startMesh(profileJson: profileJson)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARG", message: "profileJson is required", details: nil))
            }
        case "stopMesh":
            MeshManager.shared.stopMesh()
            result(nil)
        case "sendPacket":
            if let args = call.arguments as? [String: Any],
               let packetJson = args["packetJson"] as? String {
                MeshManager.shared.sendPacketFromDart(jsonStr: packetJson)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARG", message: "packetJson is required", details: nil))
            }
        case "setForegroundMode":
            MeshManager.shared.setForegroundMode()
            result(nil)
        case "setBackgroundMode":
            MeshManager.shared.setBackgroundMode()
            result(nil)
        case "setContinuousMode":
            MeshManager.shared.setContinuousMode()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - StreamHandlers
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}

class PeersStreamHandler: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.sink = nil
        return nil
    }
}

class PacketsStreamHandler: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.sink = nil
        return nil
    }
}
