package com.liita.liita

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.os.Handler
import android.os.Looper
import android.util.Log

class MeshPlugin(private val context: Context, flutterEngine: FlutterEngine) : MethodCallHandler {
    companion object {
        const val TAG = "MeshPlugin"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.liita.app/mesh")
    private val peersChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.liita.app/peers")
    private val packetsChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.liita.app/packets")

    private var meshService: MeshForegroundService? = null
    private var isBound = false

    private var peersSink: EventChannel.EventSink? = null
    private var packetsSink: EventChannel.EventSink? = null

    // RC-5: Queue method calls that arrive before the service bind completes.
    private val pendingCalls = ArrayDeque<Pair<MethodCall, Result>>()

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as MeshForegroundService.LocalBinder
            meshService = binder.getService()
            isBound = true
            setupServiceCallbacks()
            // RC-5: Drain any calls that arrived before the bind completed.
            drainPendingCalls()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            meshService = null
            isBound = false
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)

        peersChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                peersSink = events
            }
            override fun onCancel(arguments: Any?) {
                peersSink = null
            }
        })

        packetsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                packetsSink = events
            }
            override fun onCancel(arguments: Any?) {
                packetsSink = null
            }
        })

        // Bind the service so it's ready, but don't start it as foreground until startMesh is called
        val intent = Intent(context, MeshForegroundService::class.java)
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    private fun setupServiceCallbacks() {
        meshService?.onPeerDiscovered = { profileJson ->
            mainHandler.post { peersSink?.success(profileJson) }
        }
        meshService?.onPacketReceived = { packetJson ->
            mainHandler.post { packetsSink?.success(packetJson) }
        }
    }

    // RC-5: Flush all queued method calls now that the service is live.
    private fun drainPendingCalls() {
        Log.d(TAG, "[LiitaBLE] drainPendingCalls: flushing ${pendingCalls.size} queued call(s)")
        while (pendingCalls.isNotEmpty()) {
            val (call, result) = pendingCalls.removeFirst()
            dispatchMethodCall(call, result)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        // RC-5: If not yet bound, queue the call for later execution.
        if (!isBound || meshService == null) {
            Log.w(TAG, "[LiitaBLE] onMethodCall '${call.method}' queued — service not yet bound")
            pendingCalls.add(Pair(call, result))
            return
        }
        dispatchMethodCall(call, result)
    }

    private fun dispatchMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startMesh" -> {
                val profileJson = call.argument<String>("profileJson")
                if (profileJson != null) {
                    val intent = Intent(context, MeshForegroundService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    meshService?.startMesh(profileJson)
                    result.success(null)
                } else {
                    result.error("INVALID_ARG", "profileJson is required", null)
                }
            }
            "stopMesh" -> {
                meshService?.stopMesh()
                result.success(null)
            }
            "sendPacket" -> {
                val packetJson = call.argument<String>("packetJson")
                if (packetJson != null) {
                    meshService?.sendPacketFromDart(packetJson)
                    result.success(null)
                } else {
                    result.error("INVALID_ARG", "packetJson is required", null)
                }
            }
            "setForegroundMode" -> {
                meshService?.setForegroundMode()
                result.success(null)
            }
            "setBackgroundMode" -> {
                meshService?.setBackgroundMode()
                result.success(null)
            }
            "setContinuousMode" -> {
                meshService?.setContinuousMode()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun destroy() {
        if (isBound) {
            context.unbindService(serviceConnection)
            isBound = false
        }
    }
}
