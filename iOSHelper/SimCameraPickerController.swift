import UIKit
import AVFoundation

/// Custom camera picker that works in iOS Simulator using SimCameraBridge
/// Drop-in replacement for UIImagePickerController
public class SimCameraPickerController: UIViewController {

    // MARK: - Public Properties

    public weak var delegate: (UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
    public var allowsEditing: Bool = false

    // MARK: - Private Properties

    #if targetEnvironment(simulator)
    private var previewLayer: SimBridgePreviewLayer?
    #else
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    #endif

    private let captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📸", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 60)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupUI()
        setupCamera()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCamera()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(captureButton)
        view.addSubview(cancelButton)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            captureButton.widthAnchor.constraint(equalToConstant: 80),
            captureButton.heightAnchor.constraint(equalToConstant: 80),

            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        #if targetEnvironment(simulator)
        statusLabel.text = "🌉 SimCameraBridge"
        #else
        statusLabel.text = "📱 Camera"
        #endif
    }

    private func setupCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if granted {
                    #if targetEnvironment(simulator)
                    self.setupSimulatorCamera()
                    #else
                    self.setupRealCamera()
                    #endif
                } else {
                    self.statusLabel.text = "❌ Camera permission denied"
                }
            }
        }
    }

    // MARK: - Simulator Camera

    #if targetEnvironment(simulator)
    private func setupSimulatorCamera() {
        let simPreviewLayer = SimBridgePreviewLayer()
        simPreviewLayer.frame = view.bounds
        view.layer.insertSublayer(simPreviewLayer, at: 0)
        self.previewLayer = simPreviewLayer

        simPreviewLayer.startRunning()

        checkServerStatus()
    }

    private func checkServerStatus() {
        guard let url = URL(string: "http://localhost:8080/frame") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.statusLabel.text = "❌ Server not running\n💡 Run: cd macOSApp && swift run"
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.statusLabel.text = "✅ Ready"
                }
            }
        }.resume()
    }
    #endif

    // MARK: - Real Device Camera

    #if !targetEnvironment(simulator)
    private func setupRealCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            statusLabel.text = "❌ Camera error"
            return
        }

        session.addInput(videoInput)

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            photoOutput = output
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        self.previewLayer = preview

        captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async {
                self.statusLabel.text = "✅ Ready"
            }
        }
    }
    #endif

    // MARK: - Actions

    @objc private func capturePhoto() {
        #if targetEnvironment(simulator)
        captureSimulatorPhoto()
        #else
        captureRealPhoto()
        #endif
    }

    #if targetEnvironment(simulator)
    private func captureSimulatorPhoto() {
        guard let url = URL(string: "http://localhost:8080/frame") else {
            statusLabel.text = "❌ Server not available"
            return
        }

        statusLabel.text = "📸 Capturing..."

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self?.statusLabel.text = "❌ Capture failed"
                }
                return
            }

            DispatchQueue.main.async {
                self.statusLabel.text = "✅ Photo captured!"

                // Notify delegate
                let info: [UIImagePickerController.InfoKey: Any] = [
                    .originalImage: image
                ]

                self.delegate?.imagePickerController?(
                    UIImagePickerController(),
                    didFinishPickingMediaWithInfo: info
                )

                // Dismiss after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.dismiss(animated: true)
                }
            }
        }.resume()
    }
    #endif

    #if !targetEnvironment(simulator)
    private func captureRealPhoto() {
        guard let photoOutput = photoOutput else { return }

        statusLabel.text = "📸 Capturing..."

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    #endif

    @objc private func cancel() {
        delegate?.imagePickerControllerDidCancel?(UIImagePickerController())
        dismiss(animated: true)
    }

    private func stopCamera() {
        #if targetEnvironment(simulator)
        previewLayer?.stopRunning()
        #else
        captureSession?.stopRunning()
        #endif
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        #if targetEnvironment(simulator)
        previewLayer?.frame = view.bounds
        #else
        previewLayer?.frame = view.bounds
        #endif
    }
}

// MARK: - AVCapturePhotoCaptureDelegate (Real Device Only)

#if !targetEnvironment(simulator)
extension SimCameraPickerController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            statusLabel.text = "❌ Capture failed"
            return
        }

        statusLabel.text = "✅ Photo captured!"

        let info: [UIImagePickerController.InfoKey: Any] = [
            .originalImage: image
        ]

        delegate?.imagePickerController?(
            UIImagePickerController(),
            didFinishPickingMediaWithInfo: info
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.dismiss(animated: true)
        }
    }
}
#endif
