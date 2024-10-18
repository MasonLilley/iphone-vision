import UIKit
import AVFoundation

class ViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var videoOutput: AVCaptureVideoDataOutput!
    let webSocketClient = WebSocketClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
        webSocketClient.connect()
    }

    func setupCaptureSession() {
        captureSession = AVCaptureSession()

        // Configure camera input
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        // Configure video output
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Configure preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Convert imageBuffer to a UIImage or raw data
        let pixelBuffer = imageBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Create a context to render the image
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        // Encode the UIImage to JPEG data
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }

        // Send the JPEG data over WebSocket
        webSocketClient.sendFrame(data: jpegData)

        // For demonstration, log the pixel buffer's size
//        let width = CVPixelBufferGetWidth(pixelBuffer)
//        let height = CVPixelBufferGetHeight(pixelBuffer)
//        print("Captured frame: \(width)x\(height) and sent to WebSocket.")
    }
}

