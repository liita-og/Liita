package com.liita.liita

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var meshPlugin: MeshPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        meshPlugin = MeshPlugin(this, flutterEngine)
    }

    override fun onDestroy() {
        meshPlugin?.destroy()
        meshPlugin = null
        super.onDestroy()
    }
}
