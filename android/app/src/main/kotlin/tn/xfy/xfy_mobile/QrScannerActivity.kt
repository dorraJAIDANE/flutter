package tn.xfy.xfy_mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.util.Size
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Scanner QR & Codes-barres XFY 100 % natif Android (CameraX PreviewView + Google ML Kit).
 *
 * Isolé dans sa propre `ComponentActivity` (`LifecycleOwner` propre) pour éviter tout conflit
 * avec le rendu Flutter Impeller / `IndexedStack` et garantir une caméra stable, fluide et
 * continue jusqu'à détection réelle d'un QR code XFY ou bordereau.
 */
@androidx.annotation.OptIn(ExperimentalGetImage::class)
class QrScannerActivity : ComponentActivity() {

    companion object {
        const val EXTRA_SCANNED_CODE = "scanned_code"
        const val EXTRA_OPEN_MANUAL = "open_manual"
        private const val REQ_CAMERA_PERMISSION = 7042
        private const val WARMUP_MS = 450L
    }

    private lateinit var rootLayout: FrameLayout
    private lateinit var previewView: PreviewView
    private lateinit var overlayContainer: FrameLayout
    private lateinit var permissionPanel: LinearLayout
    private lateinit var statusLabel: TextView
    private lateinit var flashBtn: Button

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var barcodeScanner: BarcodeScanner? = null
    private var analysisExecutor: ExecutorService? = null

    private var useBackCamera = true
    private var torchEnabled = false
    private var openedAtMs = 0L
    private val resultDelivered = AtomicBoolean(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        analysisExecutor = Executors.newSingleThreadExecutor()
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_QR_CODE,
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_CODE_39,
                Barcode.FORMAT_CODE_93,
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_UPC_A,
                Barcode.FORMAT_DATA_MATRIX,
                Barcode.FORMAT_PDF417
            )
            .build()
        barcodeScanner = BarcodeScanning.getClient(options)

        buildUi()
        setContentView(rootLayout)

        checkAndStartCamera(requestIfMissing = true)
    }

    override fun onResume() {
        super.onResume()
        // Si l'utilisateur revient des paramètres Android après avoir activé la caméra
        if (hasCameraPermission() && camera == null && !resultDelivered.get()) {
            permissionPanel.visibility = View.GONE
            overlayContainer.visibility = View.VISIBLE
            startCamera()
        }
    }

    override fun onDestroy() {
        try {
            cameraProvider?.unbindAll()
        } catch (_: Exception) {
        }
        try {
            barcodeScanner?.close()
        } catch (_: Exception) {
        }
        analysisExecutor?.shutdownNow()
        analysisExecutor = null
        super.onDestroy()
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun buildUi() {
        rootLayout = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        // 1. CameraX PreviewView (TextureView mode = ultra-compatible Samsung/Xiaomi/Infinix/Oppo)
        previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        rootLayout.addView(previewView)

        // 2. Overlay de visée + contrôles Flash / Switch / Fermer / Saisie manuelle
        overlayContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        // Masque sombre avec fenêtre transparente + coins Indigo/Orange XFY
        overlayContainer.addView(
            ScannerOverlayView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }
        )

        // Barre supérieure (Fermer • Titre • Flash • Caméra)
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(42), dp(16), dp(12))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val closeBtn = createPillButton("✕  Fermer", bgHex = "#CC1E293B", textHex = "#FFFFFF") {
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
        topBar.addView(closeBtn)

        val titleView = TextView(this).apply {
            text = "Scanner QR XFY"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        topBar.addView(titleView)

        flashBtn = createPillButton("⚡", bgHex = "#CC1E293B", textHex = "#FFFFFF") {
            toggleTorch()
        }
        topBar.addView(flashBtn)

        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(8), dp(1))
        }
        topBar.addView(spacer)

        val switchBtn = createPillButton("🔄", bgHex = "#CC1E293B", textHex = "#FFFFFF") {
            useBackCamera = !useBackCamera
            torchEnabled = false
            updateFlashButtonUi()
            startCamera()
        }
        topBar.addView(switchBtn)

        overlayContainer.addView(topBar)

        // Zone basse (consigne + bouton saisie manuelle)
        val bottomBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(12), dp(24), dp(36))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        statusLabel = TextView(this).apply {
            text = "Pointez la caméra vers le QR code XFY"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(10), dp(16), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#B30F172A"))
                cornerRadius = dp(14).toFloat()
            }
        }
        bottomBox.addView(statusLabel)

        val gap = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(1), dp(14))
        }
        bottomBox.addView(gap)

        val manualBtn = createPillButton(
            "⌨  Saisir un N° commande manuellement",
            bgHex = "#4F46E5",
            textHex = "#FFFFFF"
        ) {
            val data = Intent().putExtra(EXTRA_OPEN_MANUAL, true)
            setResult(Activity.RESULT_OK, data)
            finish()
        }
        bottomBox.addView(manualBtn)

        overlayContainer.addView(bottomBox)
        rootLayout.addView(overlayContainer)

        // 3. Panneau de permission caméra (visible uniquement si permission refusée)
        permissionPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F0F4FF"))
            setPadding(dp(28), dp(28), dp(28), dp(28))
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val permTitle = TextView(this).apply {
            text = "Autorisez la caméra pour scanner"
            setTextColor(Color.parseColor("#0F172A"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        permissionPanel.addView(permTitle)

        val permSub = TextView(this).apply {
            text = "XFY a besoin d'accéder à la caméra pour lire vos QR codes de commandes et bordereaux."
            setTextColor(Color.parseColor("#475569"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, dp(22))
        }
        permissionPanel.addView(permSub)

        permissionPanel.addView(
            createPillButton("Activer la caméra", bgHex = "#4F46E5", textHex = "#FFFFFF") {
                checkAndStartCamera(requestIfMissing = true)
            }
        )

        val permGap1 = View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(1), dp(12)) }
        permissionPanel.addView(permGap1)

        permissionPanel.addView(
            createPillButton("Ouvrir les paramètres Android", bgHex = "#FFFFFF", textHex = "#4F46E5") {
                try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (_: Exception) {
                }
            }
        )

        val permGap2 = View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(1), dp(12)) }
        permissionPanel.addView(permGap2)

        permissionPanel.addView(
            createPillButton("Retour", bgHex = "#E2E8F0", textHex = "#0F172A") {
                setResult(Activity.RESULT_CANCELED)
                finish()
            }
        )

        rootLayout.addView(permissionPanel)
    }

    private fun createPillButton(
        label: String,
        bgHex: String,
        textHex: String,
        onClick: () -> Unit
    ): Button {
        return Button(this).apply {
            text = label
            isAllCaps = false
            setTextColor(Color.parseColor(textHex))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(16), dp(10), dp(16), dp(10))
            minHeight = dp(42)
            minWidth = dp(44)
            background = GradientDrawable().apply {
                setColor(Color.parseColor(bgHex))
                cornerRadius = dp(999).toFloat()
            }
            setOnClickListener { onClick() }
        }
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun checkAndStartCamera(requestIfMissing: Boolean) {
        if (hasCameraPermission()) {
            permissionPanel.visibility = View.GONE
            overlayContainer.visibility = View.VISIBLE
            startCamera()
        } else if (requestIfMissing) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQ_CAMERA_PERMISSION
            )
        } else {
            overlayContainer.visibility = View.GONE
            permissionPanel.visibility = View.VISIBLE
        }
    }

    @Deprecated("Handled directly on ComponentActivity")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                permissionPanel.visibility = View.GONE
                overlayContainer.visibility = View.VISIBLE
                startCamera()
            } else {
                overlayContainer.visibility = View.GONE
                permissionPanel.visibility = View.VISIBLE
            }
        }
    }

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val provider = future.get()
                cameraProvider = provider
                provider.unbindAll()

                val selector = if (useBackCamera) {
                    CameraSelector.DEFAULT_BACK_CAMERA
                } else {
                    CameraSelector.DEFAULT_FRONT_CAMERA
                }

                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

                @Suppress("DEPRECATION")
                val imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(1280, 720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                val executor = analysisExecutor ?: Executors.newSingleThreadExecutor().also {
                    analysisExecutor = it
                }

                openedAtMs = SystemClock.elapsedRealtime()

                imageAnalysis.setAnalyzer(executor) { imageProxy ->
                    if (resultDelivered.get()) {
                        imageProxy.close()
                        return@setAnalyzer
                    }
                    // Courte période de stabilisation (450 ms) pour laisser l'autofocus s'ajuster
                    if (SystemClock.elapsedRealtime() - openedAtMs < WARMUP_MS) {
                        imageProxy.close()
                        return@setAnalyzer
                    }

                    val mediaImage = imageProxy.image
                    val scanner = barcodeScanner
                    if (mediaImage == null || scanner == null) {
                        imageProxy.close()
                        return@setAnalyzer
                    }

                    val inputImage = InputImage.fromMediaImage(
                        mediaImage,
                        imageProxy.imageInfo.rotationDegrees
                    )

                    scanner.process(inputImage)
                        .addOnSuccessListener { barcodes ->
                            for (barcode in barcodes) {
                                val raw = barcode.rawValue?.trim()
                                if (!raw.isNullOrEmpty() && resultDelivered.compareAndSet(false, true)) {
                                    onBarcodeCaptured(raw)
                                    break
                                }
                            }
                        }
                        .addOnCompleteListener {
                            imageProxy.close()
                        }
                }

                camera = provider.bindToLifecycle(this, selector, preview, imageAnalysis)
                runOnUiThread {
                    statusLabel.text = "Pointez la caméra vers le QR code XFY"
                }
            } catch (e: Exception) {
                runOnUiThread {
                    statusLabel.text = "Erreur caméra : ${e.localizedMessage ?: "réessayez"}"
                }
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun onBarcodeCaptured(code: String) {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (vibrator != null && vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(70, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(70)
                }
            }
        } catch (_: Exception) {
        }

        runOnUiThread {
            val resultIntent = Intent().putExtra(EXTRA_SCANNED_CODE, code)
            setResult(Activity.RESULT_OK, resultIntent)
            finish()
        }
    }

    private fun toggleTorch() {
        val cam = camera ?: return
        if (!cam.cameraInfo.hasFlashUnit()) return
        torchEnabled = !torchEnabled
        cam.cameraControl.enableTorch(torchEnabled)
        updateFlashButtonUi()
    }

    private fun updateFlashButtonUi() {
        flashBtn.background = GradientDrawable().apply {
            setColor(Color.parseColor(if (torchEnabled) "#4F46E5" else "#CC1E293B"))
            cornerRadius = dp(999).toFloat()
        }
    }

    /** Dessine le masque semi-transparent et le cadre de visée XFY (Indigo & Orange). */
    private class ScannerOverlayView(context: Context) : View(context) {
        private val scrimPaint = Paint().apply {
            color = Color.parseColor("#880F172A")
            style = Paint.Style.FILL
        }
        private val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 6f
        }
        private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#6366F1")
            style = Paint.Style.STROKE
            strokeWidth = 11f
            strokeCap = Paint.Cap.ROUND
        }
        private val laserPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#F97316")
            style = Paint.Style.STROKE
            strokeWidth = 5f
            strokeCap = Paint.Cap.ROUND
        }

        init {
            setLayerType(LAYER_TYPE_SOFTWARE, null)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            val boxSize = (minOf(w, h) * 0.68f).coerceAtMost(760f)
            val left = (w - boxSize) / 2f
            val top = (h - boxSize) / 2f - h * 0.03f
            val right = left + boxSize
            val bottom = top + boxSize
            val radius = 44f
            val rect = RectF(left, top, right, bottom)

            // Fond assombri + fenêtre découpée transparente
            canvas.drawRect(0f, 0f, w, h, scrimPaint)
            canvas.drawRoundRect(rect, radius, radius, clearPaint)

            // Bordure blanche fine
            canvas.drawRoundRect(rect, radius, radius, borderPaint)

            // 4 coins accentués Indigo XFY
            val cLen = 58f
            // Haut-gauche
            canvas.drawLine(left, top + cLen, left, top + radius / 2, cornerPaint)
            canvas.drawLine(left + radius / 2, top, left + cLen, top, cornerPaint)
            // Haut-droite
            canvas.drawLine(right - cLen, top, right - radius / 2, top, cornerPaint)
            canvas.drawLine(right, top + radius / 2, right, top + cLen, cornerPaint)
            // Bas-gauche
            canvas.drawLine(left, bottom - cLen, left, bottom - radius / 2, cornerPaint)
            canvas.drawLine(left + radius / 2, bottom, left + cLen, bottom, cornerPaint)
            // Bas-droite
            canvas.drawLine(right - cLen, bottom, right - radius / 2, bottom, cornerPaint)
            canvas.drawLine(right, bottom - radius / 2, right, bottom - cLen, cornerPaint)

            // Ligne de visée orange XFY au centre
            val midY = (top + bottom) / 2f
            canvas.drawLine(left + 32f, midY, right - 32f, midY, laserPaint)
        }
    }
}
