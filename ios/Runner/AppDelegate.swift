import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var isPresentingScanner = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "XfyNativeBridgePlugin") {
      let channel = FlutterMethodChannel(
        name: "tn.xfy.xfy_mobile/order_monitor",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleMethodCall(call, result: result)
      }
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openNativeQrScanner":
      openNativeQrScanner(result: result)

    case "openAppSettings", "openNotificationSettings":
      DispatchQueue.main.async {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:]) { ok in
            result(ok)
          }
        } else {
          result(false)
        }
      }

    case "startMonitor", "isRunning", "consumeOpenOrdersIntent":
      result(false)

    case "stopMonitor", "syncLastSeenOrderId", "setAppForeground",
         "updatePreferences", "setLanguage",
         "isIgnoringBatteryOptimizations", "requestIgnoreBatteryOptimizations":
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let keyWindow = activeScene?.windows.first { $0.isKeyWindow } ?? activeScene?.windows.first
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func openNativeQrScanner(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(nil)
        return
      }
      if self.isPresentingScanner {
        result(nil)
        return
      }

      let status = AVCaptureDevice.authorizationStatus(for: .video)
      switch status {
      case .authorized:
        self.presentScannerController(result: result)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async {
            if granted {
              self.presentScannerController(result: result)
            } else {
              self.presentCameraPermissionAlert()
              result(nil)
            }
          }
        }
      case .denied, .restricted:
        self.presentCameraPermissionAlert()
        result(nil)
      @unknown default:
        result(nil)
      }
    }
  }

  private func presentScannerController(result: @escaping FlutterResult) {
    guard let presenter = topViewController() else {
      result(nil)
      return
    }
    isPresentingScanner = true
    let scannerVC = XfyQrScannerViewController { [weak self] payload in
      self?.isPresentingScanner = false
      result(payload)
    }
    scannerVC.modalPresentationStyle = .fullScreen
    presenter.present(scannerVC, animated: true)
  }

  private func presentCameraPermissionAlert() {
    guard let presenter = topViewController() else { return }
    let alert = UIAlertController(
      title: "Accès caméra requis",
      message: "Autorisez la caméra dans Réglages > XFY pour scanner les QR codes XFY.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
    alert.addAction(UIAlertAction(title: "Ouvrir Réglages", style: .default) { _ in
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
    })
    presenter.present(alert, animated: true)
  }
}

/// Scanner QR & codes-barres 100 % natif iOS (`AVFoundation`), calqué sur `QrScannerActivity.kt`.
final class XfyQrScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let completion: ([String: Any]?) -> Void
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "tn.xfy.qr.capture.session")

  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var captureDevice: AVCaptureDevice?
  private var hasFinished = false
  private var torchOn = false

  private let torchButton = UIButton(type: .system)
  private let reticleView = UIView()
  private let overlayMaskLayer = CAShapeLayer()

  init(completion: @escaping ([String: Any]?) -> Void) {
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupCameraSession()
    setupOverlayUi()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sessionQueue.async { [weak self] in
      guard let self = self, !self.session.isRunning else { return }
      self.session.startRunning()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    setTorch(enabled: false)
    sessionQueue.async { [weak self] in
      guard let self = self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
    updateDimmedMask()
  }

  private func setupCameraSession() {
    guard let device = AVCaptureDevice.default(for: .video) else {
      finish(with: nil)
      return
    }
    captureDevice = device

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.insertSublayer(layer, at: 0)
    previewLayer = layer

    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.session.beginConfiguration()
      if self.session.canSetSessionPreset(.high) {
        self.session.sessionPreset = .high
      }

      guard let input = try? AVCaptureDeviceInput(device: device),
            self.session.canAddInput(input) else {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.finish(with: nil) }
        return
      }
      self.session.addInput(input)

      let metadataOutput = AVCaptureMetadataOutput()
      guard self.session.canAddOutput(metadataOutput) else {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.finish(with: nil) }
        return
      }
      self.session.addOutput(metadataOutput)
      metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

      let desiredTypes: [AVMetadataObject.ObjectType] = [
        .qr,
        .code128,
        .code39,
        .ean13,
        .ean8,
        .upce,
        .pdf417,
        .dataMatrix,
        .aztec,
      ]
      let supported = desiredTypes.filter {
        metadataOutput.availableMetadataObjectTypes.contains($0)
      }
      metadataOutput.metadataObjectTypes = supported
      self.session.commitConfiguration()
    }
  }

  private func setupOverlayUi() {
    // Voile semi-transparent autour du viseur central
    overlayMaskLayer.fillRule = .evenOdd
    overlayMaskLayer.fillColor = UIColor.black.withAlphaComponent(0.52).cgColor
    view.layer.addSublayer(overlayMaskLayer)

    // Cadre de visée XFY
    reticleView.translatesAutoresizingMaskIntoConstraints = false
    reticleView.backgroundColor = .clear
    reticleView.layer.cornerRadius = 24
    reticleView.layer.borderWidth = 3
    reticleView.layer.borderColor = UIColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1.0).cgColor
    view.addSubview(reticleView)

    // Bouton Fermer
    let closeBtn = UIButton(type: .system)
    closeBtn.translatesAutoresizingMaskIntoConstraints = false
    closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeBtn.tintColor = .white
    closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    closeBtn.layer.cornerRadius = 22
    closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    view.addSubview(closeBtn)

    // Titre central
    let titleLbl = UILabel()
    titleLbl.translatesAutoresizingMaskIntoConstraints = false
    titleLbl.text = "Scanner QR XFY"
    titleLbl.textColor = .white
    titleLbl.font = .systemFont(ofSize: 17, weight: .bold)
    view.addSubview(titleLbl)

    // Bouton Lampe torche
    torchButton.translatesAutoresizingMaskIntoConstraints = false
    torchButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
    torchButton.tintColor = .white
    torchButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    torchButton.layer.cornerRadius = 22
    torchButton.addTarget(self, action: #selector(toggleTorchTapped), for: .touchUpInside)
    view.addSubview(torchButton)

    // Bulle d'instruction sous le cadre
    let hintPill = UILabel()
    hintPill.translatesAutoresizingMaskIntoConstraints = false
    hintPill.text = "  Placez le QR code XFY dans le cadre  "
    hintPill.textColor = .white
    hintPill.font = .systemFont(ofSize: 13.5, weight: .semibold)
    hintPill.backgroundColor = UIColor.black.withAlphaComponent(0.62)
    hintPill.layer.cornerRadius = 16
    hintPill.clipsToBounds = true
    hintPill.textAlignment = .center
    view.addSubview(hintPill)

    // Bouton Saisie manuelle en bas
    let manualBtn = UIButton(type: .system)
    manualBtn.translatesAutoresizingMaskIntoConstraints = false
    manualBtn.setTitle("Saisir un N° commande manuellement", for: .normal)
    manualBtn.setTitleColor(UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0), for: .normal)
    manualBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
    manualBtn.backgroundColor = .white
    manualBtn.layer.cornerRadius = 14
    manualBtn.contentEdgeInsets = UIEdgeInsets(top: 13, left: 20, bottom: 13, right: 20)
    manualBtn.addTarget(self, action: #selector(manualTapped), for: .touchUpInside)
    view.addSubview(manualBtn)

    let safe = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      closeBtn.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
      closeBtn.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
      closeBtn.widthAnchor.constraint(equalToConstant: 44),
      closeBtn.heightAnchor.constraint(equalToConstant: 44),

      torchButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
      torchButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
      torchButton.widthAnchor.constraint(equalToConstant: 44),
      torchButton.heightAnchor.constraint(equalToConstant: 44),

      titleLbl.centerYAnchor.constraint(equalTo: closeBtn.centerYAnchor),
      titleLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      reticleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      reticleView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
      reticleView.widthAnchor.constraint(equalToConstant: 260),
      reticleView.heightAnchor.constraint(equalToConstant: 260),

      hintPill.topAnchor.constraint(equalTo: reticleView.bottomAnchor, constant: 22),
      hintPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      hintPill.heightAnchor.constraint(equalToConstant: 34),

      manualBtn.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -22),
      manualBtn.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
      manualBtn.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
    ])
  }

  private func updateDimmedMask() {
    let fullPath = UIBezierPath(rect: view.bounds)
    let cutout = UIBezierPath(roundedRect: reticleView.frame, cornerRadius: 24)
    fullPath.append(cutout)
    overlayMaskLayer.path = fullPath.cgPath
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !hasFinished else { return }
    for obj in metadataObjects {
      if let readable = obj as? AVMetadataMachineReadableCodeObject,
         let value = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
         !value.isEmpty {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        finish(with: ["code": value])
        return
      }
    }
  }

  @objc private func closeTapped() {
    finish(with: nil)
  }

  @objc private func manualTapped() {
    finish(with: ["manual": true])
  }

  @objc private func toggleTorchTapped() {
    setTorch(enabled: !torchOn)
  }

  private func setTorch(enabled: Bool) {
    guard let device = captureDevice, device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      device.torchMode = enabled ? .on : .off
      device.unlockForConfiguration()
      torchOn = enabled
      let iconName = enabled ? "bolt.fill" : "bolt.slash.fill"
      torchButton.setImage(UIImage(systemName: iconName), for: .normal)
      torchButton.tintColor = enabled
        ? UIColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)
        : .white
    } catch {
      // Ignore torch error
    }
  }

  private func finish(with payload: [String: Any]?) {
    guard !hasFinished else { return }
    hasFinished = true
    setTorch(enabled: false)
    sessionQueue.async { [weak self] in
      self?.session.stopRunning()
    }
    dismiss(animated: true) { [weak self] in
      self?.completion(payload)
    }
  }
}
