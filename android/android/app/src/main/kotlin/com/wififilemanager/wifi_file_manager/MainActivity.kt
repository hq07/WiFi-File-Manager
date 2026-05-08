package com.wififilemanager.wifi_file_manager

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        var channel: MethodChannel? = null
    }

    private var safFolderPicker: SafFolderPicker? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wififilemanager/media")

        safFolderPicker = SafFolderPicker(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wififilemanager/saf")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolderSaf" -> safFolderPicker?.pickFolderSaf(result)
                    "startCopy" -> safFolderPicker?.startCopy(result)
                    "cancelCopy" -> {
                        safFolderPicker?.cancelCopy()
                        result.success(null)
                    }
                    "listDirectory" -> {
                        val uri = call.arguments as String
                        safFolderPicker?.listDirectory(uri, result)
                    }
                    "readSafBytes" -> {
                        val uri = call.arguments as String
                        safFolderPicker?.readSafBytes(uri, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        safFolderPicker?.onActivityResult(requestCode, resultCode, data)
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        channel = null
        super.onDestroy()
    }
}
