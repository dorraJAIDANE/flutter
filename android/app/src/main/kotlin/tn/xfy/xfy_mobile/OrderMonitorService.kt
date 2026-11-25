package tn.xfy.xfy_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * Service Android léger (Foreground Service dataSync) qui continue de surveiller
 * les nouvelles commandes XFY même quand l'utilisateur passe sur Chrome, WhatsApp
 * ou verrouille son écran — et déclenche instantanément une notification sonore
 * avec la sonnerie XFY (`res/raw/notification.mp3`).
 */
class OrderMonitorService : Service() {

    companion object {
        const val PREFS_NAME = "xfy_native_order_monitor"
        const val KEY_STORE_ID = "store_id"
        const val KEY_STORE_NAME = "store_name"
        const val KEY_TOKEN = "token"
        const val KEY_LAST_SEEN_ID = "last_seen_order_id"
        const val KEY_NOTIF_ENABLED = "notif_enabled"
        const val KEY_SOUND_ENABLED = "sound_enabled"
        const val KEY_LANG = "app_lang"
        const val KEY_APP_FOREGROUND = "app_foreground"
        const val KEY_RUNNING = "service_running"

        const val CHANNEL_STATUS_ID = "xfy_monitor_status_v1"
        const val CHANNEL_ORDER_SOUND_ID = "xfy_new_orders_money_v3"
        const val CHANNEL_ORDER_SILENT_ID = "xfy_new_orders_silent_v3"
        const val FOREGROUND_NOTIF_ID = 40001
        const val EXTRA_OPEN_ORDERS = "xfy_open_orders_tab"

        private const val POLL_INTERVAL_SECONDS = 12L
        private const val API_RECENT_BASE = "https://xfy.tn/api/commande/recent/"

        @Volatile
        var isServiceRunning: Boolean = false

        fun ensureOrderChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Nettoyer les anciens canaux v2 pour forcer Android à adopter la nouvelle sonnerie Money
            try {
                nm.deleteNotificationChannel("xfy_new_orders_sound_v2")
                nm.deleteNotificationChannel("xfy_new_orders_silent_v2")
            } catch (_: Exception) {}

            // 1. Canal discret pour l'état "Surveillance active"
            if (nm.getNotificationChannel(CHANNEL_STATUS_ID) == null) {
                val statusChannel = NotificationChannel(
                    CHANNEL_STATUS_ID,
                    "Surveillance commandes XFY",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Maintient la réception des alertes de commandes en arrière-plan"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
                nm.createNotificationChannel(statusChannel)
            }

            // 2. Canal haute priorité AVEC la sonnerie Money (`res/raw/money_chime.wav`)
            if (nm.getNotificationChannel(CHANNEL_ORDER_SOUND_ID) == null) {
                val soundUri = Uri.parse("android.resource://${context.packageName}/${R.raw.money_chime}")
                val audioAttrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val orderSoundChannel = NotificationChannel(
                    CHANNEL_ORDER_SOUND_ID,
                    "Nouvelles commandes XFY (Money)",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alertes sonores Money instantanées à chaque nouvelle commande reçue"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 300, 150, 300)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(soundUri, audioAttrs)
                }
                nm.createNotificationChannel(orderSoundChannel)
            }

            // 3. Canal haute priorité SANS sonnerie (si l'utilisateur coupe la sonnerie)
            if (nm.getNotificationChannel(CHANNEL_ORDER_SILENT_ID) == null) {
                val silentChannel = NotificationChannel(
                    CHANNEL_ORDER_SILENT_ID,
                    "Nouvelles commandes XFY (Silencieux)",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alertes visuelles sans sonnerie"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 220, 120, 220)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(null, null)
                }
                nm.createNotificationChannel(silentChannel)
            }
        }
    }

    private var scheduler: ScheduledExecutorService? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureOrderChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureOrderChannels(this)

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val storeId = prefs.getLong(KEY_STORE_ID, -1L)
        val token = prefs.getString(KEY_TOKEN, "") ?: ""
        val storeName = prefs.getString(KEY_STORE_NAME, "Votre boutique") ?: "Votre boutique"

        if (storeId <= 0 || token.isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        val ongoingNotif = buildOngoingNotification(storeName)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    FOREGROUND_NOTIF_ID,
                    ongoingNotif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(FOREGROUND_NOTIF_ID, ongoingNotif)
            }
            isServiceRunning = true
            prefs.edit().putBoolean(KEY_RUNNING, true).apply()
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }

        restartPollingLoop()
        return START_STICKY
    }

    override fun onDestroy() {
        isServiceRunning = false
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RUNNING, false)
            .apply()
        scheduler?.shutdownNow()
        scheduler = null
        super.onDestroy()
    }

    private fun restartPollingLoop() {
        scheduler?.shutdownNow()
        scheduler = Executors.newSingleThreadScheduledExecutor()
        scheduler?.scheduleWithFixedDelay(
            { checkRecentOrdersSafely() },
            5L,
            POLL_INTERVAL_SECONDS,
            TimeUnit.SECONDS
        )
    }

    private fun buildOngoingNotification(storeName: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_ORDERS, true)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 1001, openIntent, piFlags)

        val lang = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LANG, "fr") ?: "fr"
        val ongoingTitle = when (lang) {
            "en" -> "XFY • Order alerts active"
            "ar" -> "XFY • تنبيهات الطلبات مفعّلة"
            else -> "XFY • Alertes commandes actives"
        }
        val ongoingText = when (lang) {
            "en" -> "Live monitoring for $storeName"
            "ar" -> "مراقبة فورية لمتجر $storeName"
            else -> "Surveillance en direct de $storeName"
        }

        return NotificationCompat.Builder(this, CHANNEL_STATUS_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(ongoingTitle)
            .setContentText(ongoingText)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun checkRecentOrdersSafely() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val notifEnabled = prefs.getBoolean(KEY_NOTIF_ENABLED, true)
            if (!notifEnabled) return

            // Si l'app Flutter est ouverte au premier plan, RealtimeOrderWatcher (STOMP + poll)
            // gère déjà les alertes instantanées + bannière in-app sans doublon.
            if (prefs.getBoolean(KEY_APP_FOREGROUND, false)) return

            val storeId = prefs.getLong(KEY_STORE_ID, -1L)
            val token = prefs.getString(KEY_TOKEN, "") ?: ""
            if (storeId <= 0 || token.isBlank()) return

            val url = URL("$API_RECENT_BASE$storeId")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10000
                readTimeout = 12000
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }

            try {
                if (conn.responseCode !in 200..299) return
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                if (body.isBlank()) return

                val arr = JSONArray(body)
                if (arr.length() == 0) return

                var lastSeen = prefs.getLong(KEY_LAST_SEEN_ID, -1L)
                val orders = mutableListOf<JSONObject>()
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    if (obj.optLong("id", 0L) > 0L) {
                        orders.add(obj)
                    }
                }
                if (orders.isEmpty()) return

                // Trier par ID croissant pour notifier dans l'ordre d'arrivée
                orders.sortBy { it.optLong("id", 0L) }

                // Sécurité : si jamais lastSeen n'était pas encore initialisé (< 0), on l'initialise sans spammer l'historique
                if (lastSeen < 0L) {
                    val maxId = orders.last().optLong("id", 0L)
                    prefs.edit().putLong(KEY_LAST_SEEN_ID, maxId).apply()
                    return
                }

                val soundEnabled = prefs.getBoolean(KEY_SOUND_ENABLED, true)
                for (order in orders) {
                    val orderId = order.optLong("id", 0L)
                    if (orderId > lastSeen) {
                        lastSeen = orderId
                        prefs.edit().putLong(KEY_LAST_SEEN_ID, lastSeen).apply()
                        postOrderHeadsUpNotification(order, soundEnabled)
                    }
                }
            } finally {
                conn.disconnect()
            }
        } catch (_: Exception) {
            // Réseau momentanément indisponible — prochaine vérification dans 12s
        }
    }

    private fun postOrderHeadsUpNotification(order: JSONObject, soundEnabled: Boolean) {
        val orderId = order.optLong("id", 0L)
        val lang = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LANG, "fr") ?: "fr"
        val defaultClient = when (lang) {
            "en" -> "New customer"
            "ar" -> "حريف جديد"
            else -> "Nouveau client"
        }
        val nom = order.optString("nom", defaultClient).ifBlank { defaultClient }
        val produit = order.optString("produit", "").trim()
        val gov = order.optString("gouvernorat", "").trim()
        val ville = order.optString("ville", "").trim()
        val total = order.optDouble("total", Double.NaN)

        val totalPart = if (!total.isNaN() && total > 0) {
            val formatted = if (total == total.roundToInt().toDouble()) {
                "${total.roundToInt()} DT"
            } else {
                String.format("%.2f DT", total)
            }
            " • $formatted"
        } else {
            ""
        }

        val prefix = when (lang) {
            "en" -> "New order"
            "ar" -> "طلب جديد"
            else -> "Nouvelle commande"
        }
        val title = "$prefix$totalPart"
        val loc = gov.ifEmpty { ville }
        val bodyBuilder = StringBuilder(nom)
        if (produit.isNotEmpty()) bodyBuilder.append(" • ").append(produit)
        if (loc.isNotEmpty()) bodyBuilder.append(" (").append(loc).append(")")

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_ORDERS, true)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            (orderId % 100000L).toInt(),
            openIntent,
            piFlags
        )

        val channelId = if (soundEnabled) CHANNEL_ORDER_SOUND_ID else CHANNEL_ORDER_SILENT_ID
        val soundUri = Uri.parse("android.resource://$packageName/${R.raw.money_chime}")

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setColor(0xFF4F46E5.toInt())
            .setContentTitle(title)
            .setContentText(bodyBuilder.toString())
            .setStyle(NotificationCompat.BigTextStyle().bigText(bodyBuilder.toString()))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 300, 150, 300))
            .setContentIntent(pendingIntent)

        if (soundEnabled) {
            builder.setSound(soundUri)
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify((orderId % 100000L).toInt(), builder.build())
    }
}
