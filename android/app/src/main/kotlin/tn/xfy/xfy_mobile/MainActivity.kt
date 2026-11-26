package tn.xfy.xfy_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "tn.xfy.xfy_mobile/order_monitor"
        private const val REQ_QR_SCANNER = 8190
    }

    private var methodChannel: MethodChannel? = null
    private var pendingOpenOrdersTab: Boolean = false
    private var pendingQrScanResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OrderMonitorService.ensureOrderChannels(this)

        if (intent?.getBooleanExtra(OrderMonitorService.EXTRA_OPEN_ORDERS, false) == true) {
            pendingOpenOrdersTab = true
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(OrderMonitorService.PREFS_NAME, Context.MODE_PRIVATE)
                when (call.method) {
                    "startMonitor" -> {
                        val storeId = (call.argument<Number>("storeId"))?.toLong() ?: -1L
                        val storeName = call.argument<String>("storeName") ?: "Ma boutique"
                        val token = call.argument<String>("token") ?: ""
                        val lastSeenOrderId = (call.argument<Number>("lastSeenOrderId"))?.toLong() ?: 0L
                        val notifEnabled = call.argument<Boolean>("notificationsEnabled") ?: true
                        val soundEnabled = call.argument<Boolean>("soundEnabled") ?: true
                        val soundKey = call.argument<String>("soundKey") ?: OrderMonitorService.DEFAULT_SOUND_KEY
                        val language = call.argument<String>("language") ?: "fr"
                        val currentStored = prefs.getLong(OrderMonitorService.KEY_LAST_SEEN_ID, -1L)
                        val prevStore = prefs.getLong(OrderMonitorService.KEY_STORE_ID, -1L)
                        val effectiveLastSeen = if (prevStore == storeId && currentStored > lastSeenOrderId) {
                            currentStored
                        } else {
                            lastSeenOrderId
                        }

                        prefs.edit()
                            .putLong(OrderMonitorService.KEY_STORE_ID, storeId)
                            .putString(OrderMonitorService.KEY_STORE_NAME, storeName)
                            .putString(OrderMonitorService.KEY_TOKEN, token)
                            .putLong(OrderMonitorService.KEY_LAST_SEEN_ID, effectiveLastSeen)
                            .putBoolean(OrderMonitorService.KEY_NOTIF_ENABLED, notifEnabled)
                            .putBoolean(OrderMonitorService.KEY_SOUND_ENABLED, soundEnabled)
                            .putString(OrderMonitorService.KEY_SOUND_KEY, soundKey)
                            .putString(OrderMonitorService.KEY_LANG, language)
                            .apply()

                        if (storeId > 0 && token.isNotBlank() && notifEnabled) {
                            val serviceIntent = Intent(this@MainActivity, OrderMonitorService::class.java)
                            try {
                                ContextCompat.startForegroundService(this@MainActivity, serviceIntent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        } else {
                            stopService(Intent(this@MainActivity, OrderMonitorService::class.java))
                            result.success(false)
                        }
                    }

                    "stopMonitor" -> {
                        stopService(Intent(this@MainActivity, OrderMonitorService::class.java))
                        result.success(true)
                    }

                    "syncLastSeenOrderId" -> {
                        val orderId = (call.argument<Number>("orderId"))?.toLong() ?: 0L
                        val current = prefs.getLong(OrderMonitorService.KEY_LAST_SEEN_ID, 0L)
                        if (orderId > current) {
                            prefs.edit().putLong(OrderMonitorService.KEY_LAST_SEEN_ID, orderId).apply()
                        }
                        result.success(true)
                    }

                    "setAppForeground" -> {
                        val fg = call.argument<Boolean>("foreground") ?: true
                        prefs.edit().putBoolean(OrderMonitorService.KEY_APP_FOREGROUND, fg).apply()
                        result.success(true)
                    }

                    "updatePreferences" -> {
                        val notifEnabled = call.argument<Boolean>("notificationsEnabled") ?: true
                        val soundEnabled = call.argument<Boolean>("soundEnabled") ?: true
                        val soundKey = call.argument<String>("soundKey")
                        val language = call.argument<String>("language")
                        val editor = prefs.edit()
                            .putBoolean(OrderMonitorService.KEY_NOTIF_ENABLED, notifEnabled)
                            .putBoolean(OrderMonitorService.KEY_SOUND_ENABLED, soundEnabled)
                        if (!soundKey.isNullOrBlank()) {
                            editor.putString(OrderMonitorService.KEY_SOUND_KEY, soundKey)
                        }
                        if (!language.isNullOrBlank()) {
                            editor.putString(OrderMonitorService.KEY_LANG, language)
                        }
                        editor.apply()
                        if (!notifEnabled) {
                            stopService(Intent(this@MainActivity, OrderMonitorService::class.java))
                        }
                        result.success(true)
                    }

                    "setSoundKey" -> {
                        val soundKey = call.argument<String>("soundKey") ?: OrderMonitorService.DEFAULT_SOUND_KEY
                        prefs.edit().putString(OrderMonitorService.KEY_SOUND_KEY, soundKey).apply()
                        result.success(true)
                    }

                    "setLanguage" -> {
                        val language = call.argument<String>("language") ?: "fr"
                        prefs.edit().putString(OrderMonitorService.KEY_LANG, language).apply()
                        result.success(true)
                    }

                    "isRunning" -> {
                        result.success(OrderMonitorService.isServiceRunning)
                    }

                    "consumeOpenOrdersIntent" -> {
                        val shouldOpen = pendingOpenOrdersTab
                        pendingOpenOrdersTab = false
                        result.success(shouldOpen)
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                try {
                                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                    result.success(true)
                                } catch (_: Exception) {
                                    result.success(false)
                                }
                            }
                        } else {
                            result.success(true)
                        }
                    }

                    "openNotificationSettings" -> {
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                }
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }

                    "openAppSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }

                    "openNativeQrScanner" -> {
                        if (pendingQrScanResult != null) {
                            result.success(null)
                        } else {
                            pendingQrScanResult = result
                            try {
                                val scanIntent = Intent(this@MainActivity, QrScannerActivity::class.java)
                                @Suppress("DEPRECATION")
                                startActivityForResult(scanIntent, REQ_QR_SCANNER)
                            } catch (e: Exception) {
                                pendingQrScanResult = null
                                result.error("SCANNER_LAUNCH_FAILED", e.localizedMessage, null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    @Deprecated("Required for FlutterActivity native QR result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_QR_SCANNER) {
            val callback = pendingQrScanResult
            pendingQrScanResult = null
            if (callback == null) return

            if (resultCode == Activity.RESULT_OK && data != null) {
                val openManual = data.getBooleanExtra(QrScannerActivity.EXTRA_OPEN_MANUAL, false)
                val code = data.getStringExtra(QrScannerActivity.EXTRA_SCANNED_CODE)
                if (openManual) {
                    callback.success(mapOf("manual" to true))
                } else if (!code.isNullOrBlank()) {
                    callback.success(mapOf("code" to code))
                } else {
                    callback.success(null)
                }
            } else {
                callback.success(null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(OrderMonitorService.EXTRA_OPEN_ORDERS, false)) {
            methodChannel?.invokeMethod("openOrdersTab", null)
        }
    }
}
