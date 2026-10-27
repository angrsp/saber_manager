package com.sabermanager.app

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Canale "saber_manager/bluetooth" (lib/services/bluetooth_access.dart):
// versione di Android e richiesta all'utente di accendere il Bluetooth.
class MainActivity : FlutterActivity() {
    private var pendingEnable: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saber_manager/bluetooth")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "requestEnable" -> requestEnable(result)
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun requestEnable(result: MethodChannel.Result) {
        if (pendingEnable != null) {
            result.error("busy", "Bluetooth enable request already pending", null)
            return
        }
        try {
            pendingEnable = result
            startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_BT)
        } catch (e: Exception) {
            pendingEnable = null
            result.error("failed", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ENABLE_BT) {
            pendingEnable?.success(resultCode == RESULT_OK)
            pendingEnable = null
        }
    }

    companion object {
        private const val REQUEST_ENABLE_BT = 4242
    }
}
