import AVFoundation
import UIKit

#if targetEnvironment(simulator)

/// SimCameraBridge - Bridge MacBook camera to iOS Simulator
/// Usage: Replace AVCaptureSession with SimBridgeCaptureSession
/// Make sure SimCameraBridge macOS app is running.

// MARK: - HTTP Streaming Preview Layer

public class SimBridgePreviewLayer: CALayer {
    private var displayLink: CADisplayLink?
    private let imageLayer = CALayer()
    private var isRunning = false

    public override init() {
        super.init()
        setupLayer()
    }

    public override init(layer: Any) {
        super.init(layer: layer)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        imageLayer.contentsGravity = .resizeAspectFill
        addSublayer(imageLayer)
        print("🌉 SimBridgePreviewLayer: Initialized")
    }

    public override func layoutSublayers() {
        super.layoutSublayers()
        imageLayer.frame = bounds
    }

    public func startRunning() {
        guard !isRunning else { return }
        isRunning = true

        print("🎬 SimBridgePreviewLayer: Starting stream from http://localhost:8080")

        displayLink = CADisplayLink(target: self, selector: #selector(fetchFrame))
        displayLink?.preferredFramesPerSecond = 30
        displayLink?.add(to: .main, forMode: .common)
    }

    public func stopRunning() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        print("⏹ SimBridgePreviewLayer: Stopped")
    }

    @objc private func fetchFrame() {
        guard isRunning else { return }
        guard let url = URL(string: "http://localhost:8080/frame") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                if let error = error {
                    print("⚠️ SimBridgePreviewLayer: \(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                self.imageLayer.contents = cgImage
            }
        }.resume()
    }
}

// MARK: - Custom Capture Session

public class SimBridgeCaptureSession: AVCaptureSession {
    private var displayLink: CADisplayLink?
    private var isStreaming = false
    private var frameCount = 0

    public override func startRunning() {
        super.startRunning()
        print("🎬 SimBridgeCaptureSession: Starting")

        checkServerConnection()

        displayLink = CADisplayLink(target: self, selector: #selector(fetchFrame))
        displayLink?.preferredFramesPerSecond = 30
        displayLink?.add(to: .main, forMode: .common)

        isStreaming = true
    }

    public override func stopRunning() {
        super.stopRunning()
        displayLink?.invalidate()
        displayLink = nil
        isStreaming = false
        print("⏹ SimBridgeCaptureSession: Stopped")
    }

    private func checkServerConnection() {
        guard let url = URL(string: "http://localhost:8080/frame") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ SimBridgeCaptureSession: Server not reachable")
                print("💡 Run: cd macOSApp && swift run")
            } else {
                print("✅ SimBridgeCaptureSession: Connected to server")
            }
        }.resume()
    }

    @objc private func fetchFrame() {
        guard isStreaming else { return }
        guard let url = URL(string: "http://localhost:8080/frame") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                return
            }

            self.frameCount += 1
            if self.frameCount % 30 == 0 {
                print("📸 SimBridgeCaptureSession: \(self.frameCount) frames received")
            }

            guard let pixelBuffer = self.createPixelBuffer(from: cgImage) else { return }
            guard let sampleBuffer = self.createSampleBuffer(from: pixelBuffer) else { return }

            DispatchQueue.main.async {
                if let output = self.outputs.first as? AVCaptureVideoDataOutput,
                   let connection = output.connections.first,
                   let delegate = output.sampleBufferDelegate,
                   let queue = output.sampleBufferCallbackQueue {
                    queue.async {
                        delegate.captureOutput?(output, didOutput: sampleBuffer, from: connection)
                    }
                }
            }
        }.resume()
    }

    private func createPixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            cgImage.width,
            cgImage.height,
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CIContext()
        context.render(CIImage(cgImage: cgImage), to: buffer)

        return buffer
    }

    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard let formatDesc = formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        timingInfo.duration = CMTime(seconds: 1.0/30.0, preferredTimescale: 600)
        timingInfo.decodeTimeStamp = .invalid

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}

// MARK: - Auto Setup

private class SimBridgeAutoSetup {
    static let shared = SimBridgeAutoSetup()

    private init() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🌉 SimCameraBridge Active")
        print("📡 Server: http://localhost:8080")
        print("💡 Make sure macOS app is running!")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

private let autoSetupTrigger: Void = {
    _ = SimBridgeAutoSetup.shared
}()

#endif
