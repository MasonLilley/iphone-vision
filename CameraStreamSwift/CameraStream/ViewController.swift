import UIKit
import AVFoundation

class ViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var videoOutput: AVCaptureVideoDataOutput!
    var webSocketClient = WebSocketClient()
    let connectedDot = UIView()
    let reconnectButton = UIButton()
    var useSelfieCamera = false
    var connectionStatusTimer: Timer?
    var imageContext: CIContext?
    var previousFrameTime = CFAbsoluteTimeGetCurrent()
    var adaptiveQuality = true
    var jpegCompressionQuality: CGFloat = 0.5
    
    public static var currentIP = "192.168.0.39"
    public static var currentPort = "6789"

    override func viewDidLoad() {
        super.viewDidLoad()
        
        imageContext = CIContext(options: [.useSoftwareRenderer: false])
        
        setupCaptureSession()
        setupWebSocketClient()
        
        setupReconnectButton()
        setupSwapCameraButton()
        setupIPAddressButton()
        setupConnectedDisplay()
        setupQualityControl()
        
        connectionStatusTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateConnectionState), userInfo: nil, repeats: true)
    }
    
    func setupWebSocketClient(ip: String = currentIP, port: String = currentPort) {
        let urlString = "ws://\(ip):\(port)"
        guard let url = URL(string: urlString) else { return }
        webSocketClient = WebSocketClient(url: url)
        webSocketClient.connect()
        
        webSocketClient.onBackpressureCallback = { [weak self] pressure in
            guard let self = self, self.adaptiveQuality else { return }
            
            DispatchQueue.main.async {
                if pressure > 0.8 {
                    self.jpegCompressionQuality = max(0.2, self.jpegCompressionQuality - 0.1)
                    framesToSkip = min(5, framesToSkip + 1)
                    print("⚠️ High backpressure: Lower quality to \(self.jpegCompressionQuality), skip \(framesToSkip) frames")
                } else if pressure < 0.2 {
                    self.jpegCompressionQuality = min(0.6, self.jpegCompressionQuality + 0.05)
                    framesToSkip = max(0, framesToSkip - 1)
                    print("✓ Low backpressure: Increase quality to \(self.jpegCompressionQuality), skip \(framesToSkip) frames")
                }
            }
        }
    }
    
    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        captureSession.sessionPreset = .medium
        
        let cameraPosition: AVCaptureDevice.Position = useSelfieCamera ? .front : .back
        
        let wideAngleCamera: AVCaptureDevice? = {
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) {
                return device
            }
            return nil
        }()

        guard let videoDevice = wideAngleCamera else {
            print("Wide-angle camera not available, falling back to standard camera.")
            return
        }
        
        do {
            try videoDevice.lockForConfiguration()
            
            if videoDevice.activeFormat.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0 >= 30 {
                videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            }
            
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            
            videoDevice.unlockForConfiguration()
        } catch {
            print("Error configuring device: \(error)")
        }
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video input: \(error)")
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func setupQualityControl() {
        let qualityButton = UIButton()
        qualityButton.setTitle("Quality", for: .normal)
        qualityButton.translatesAutoresizingMaskIntoConstraints = false
        qualityButton.addTarget(self, action: #selector(showQualityDialog), for: .touchUpInside)
        
        qualityButton.tintColor = .systemOrange
        qualityButton.layer.borderColor = UIColor.white.cgColor
        qualityButton.layer.borderWidth = 1
        qualityButton.layer.cornerRadius = 8
        
        view.addSubview(qualityButton)

        NSLayoutConstraint.activate([
            qualityButton.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: -100),
            qualityButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 775),
            qualityButton.widthAnchor.constraint(equalToConstant: 80),
            qualityButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc func showQualityDialog() {
        let alert = UIAlertController(title: "Stream Quality",
                                     message: "Select streaming quality:",
                                     preferredStyle: .alert)
                                     
        alert.addAction(UIAlertAction(title: "Low Latency", style: .default) { _ in
            self.jpegCompressionQuality = 0.3
            framesToSkip = 1
            sendFractionNumerator = 2
            sendFractionDenominator = 3
            self.adaptiveQuality = true
        })
        
        alert.addAction(UIAlertAction(title: "Medium Quality", style: .default) { _ in
            self.jpegCompressionQuality = 0.5
            framesToSkip = 0
            sendFractionNumerator = 1
            sendFractionDenominator = 1
            self.adaptiveQuality = true
        })
        
        alert.addAction(UIAlertAction(title: "High Quality", style: .default) { _ in
            self.jpegCompressionQuality = 0.7
            framesToSkip = 0
            sendFractionNumerator = 1
            sendFractionDenominator = 1
            self.adaptiveQuality = false
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func setupSwapCameraButton() {
        let swapCameraButton = UIButton()
        
        let swapCameraImage = UIImage(systemName: "camera.on.rectangle")
        swapCameraButton.setImage(swapCameraImage, for: .normal)
        
        swapCameraButton.tintColor = .systemOrange
        swapCameraButton.imageView?.contentMode = .scaleAspectFit
        swapCameraButton.translatesAutoresizingMaskIntoConstraints = false
        swapCameraButton.addTarget(self, action: #selector(swapCamera), for: .touchUpInside)
        view.addSubview(swapCameraButton)

        NSLayoutConstraint.activate([
            swapCameraButton.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            swapCameraButton.topAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            swapCameraButton.widthAnchor.constraint(equalToConstant: 200),
            swapCameraButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc func swapCamera() {
        captureSession.stopRunning()
        
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        useSelfieCamera = !useSelfieCamera
        setupCaptureSession()
    }

    func setupIPAddressButton() {
        let ipButton = UIButton()
        ipButton.setTitle("Set IP & Port", for: .normal)
        ipButton.translatesAutoresizingMaskIntoConstraints = false
        ipButton.addTarget(self, action: #selector(showIPAddressDialog), for: .touchUpInside)
        view.addSubview(ipButton)

        NSLayoutConstraint.activate([
            ipButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ipButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 775),
            ipButton.widthAnchor.constraint(equalToConstant: 200),
            ipButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc func showIPAddressDialog() {
        let alert = UIAlertController(title: "Set IP Address and Port", message: "Enter the IP address and port:", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "IP Address"
            textField.text = "192.168.0.139"
        }
        alert.addTextField { textField in
            textField.placeholder = "Port"
            textField.text = "6789"
        }

        let confirmAction = UIAlertAction(title: "Connect", style: .default) { _ in
            let ipField = alert.textFields![0]
            let portField = alert.textFields![1]
            if let ip = ipField.text, let port = portField.text {
                self.setupWebSocketClient(ip: ip, port: port)
                self.webSocketClient.connect()
                
                ViewController.currentIP = ip
                ViewController.currentPort = port
            }
        }

        alert.addAction(confirmAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    func setupReconnectButton() {
        reconnectButton.setTitle("Reconnect", for: .normal)
        reconnectButton.translatesAutoresizingMaskIntoConstraints = false
        reconnectButton.addTarget(self, action: #selector(reconnectWebSocket), for: .touchUpInside)

        reconnectButton.addTarget(self, action: #selector(buttonPressed), for: .touchDown)
        reconnectButton.addTarget(self, action: #selector(buttonReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        reconnectButton.layer.borderColor = UIColor.white.cgColor
        reconnectButton.layer.borderWidth = 2
        reconnectButton.layer.cornerRadius = 10
        
        view.addSubview(reconnectButton)
        
        NSLayoutConstraint.activate([
            reconnectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reconnectButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            reconnectButton.widthAnchor.constraint(equalToConstant: 200),
            reconnectButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc func buttonPressed() {
        UIView.animate(withDuration: 0.1) {
            self.reconnectButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }

    @objc func buttonReleased() {
        UIView.animate(withDuration: 0.1) {
            self.reconnectButton.transform = CGAffineTransform.identity
        }
    }

    @objc func reconnectWebSocket() {
        webSocketClient.disconnect()
        webSocketClient.connect()
    }
    
    func updateConnectedDot(isConnected: Bool) {
        connectedDot.backgroundColor = isConnected ? .green : .red
    }
    
    @objc func updateConnectionState() {
        updateConnectedDot(isConnected: webSocketClient.isConnected)
    }
    
    func setupConnectedDisplay() {
        connectedDot.backgroundColor = .red
        connectedDot.translatesAutoresizingMaskIntoConstraints = false
        connectedDot.layer.cornerRadius = 15 // half of constraints
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(getNewSendFraction))
        connectedDot.addGestureRecognizer(tapGestureRecognizer)
        connectedDot.isUserInteractionEnabled = true

        view.addSubview(connectedDot)

        NSLayoutConstraint.activate([
            connectedDot.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 350),
            connectedDot.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -75),
            connectedDot.widthAnchor.constraint(equalToConstant: 30),
            connectedDot.heightAnchor.constraint(equalToConstant: 30)
        ])
        updateConnectedDot(isConnected: webSocketClient.isConnected)
    }
    
    @objc func getNewSendFraction() {
        let alert = UIAlertController(title: "Set fraction of frames NOT to send", message: "Enter fraction:", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Numerator"
            textField.text = "\(sendFractionNumerator)"
        }
        alert.addTextField { textField in
            textField.placeholder = "Denominator"
            textField.text = "\(sendFractionDenominator)"
        }

        let confirmAction = UIAlertAction(title: "Confirm", style: .default) { _ in
            if let numeratorText = alert.textFields?[0].text,
               let denominatorText = alert.textFields?[1].text,
               let numerator = Int(numeratorText),
               let denominator = Int(denominatorText), denominator != 0 {
                
                sendFractionNumerator = numerator
                sendFractionDenominator = denominator
                print("Fraction updated to \(numerator)/\(denominator)")
            } else {
                // Show an alert for invalid input
                let invalidInputAlert = UIAlertController(title: "Invalid Input", message: "Please enter valid numerator and denominator.", preferredStyle: .alert)
                invalidInputAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(invalidInputAlert, animated: true, completion: nil)
            }
        }

        alert.addAction(confirmAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}

private var frameCounter = 0
private var framesToSkip = 0
private var sendFractionNumerator = 1
private var sendFractionDenominator = 1

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - previousFrameTime
            previousFrameTime = now
            
            if framesToSkip > 0 {
                framesToSkip -= 1
                return
            }
            
            frameCounter += 1
            if sendFractionNumerator != sendFractionDenominator &&
               frameCounter % sendFractionDenominator >= sendFractionDenominator - sendFractionNumerator {
                return
            }
            
            guard webSocketClient.isConnected else {
                return
            }
            
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
            
            var jpegData: Data?
            
            if let context = imageContext {
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    
                    if let data = CFDataCreateMutable(nil, 0) {
                        if let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) {
                            let options: [CFString: Any] = [
                                kCGImageDestinationLossyCompressionQuality: jpegCompressionQuality
                            ]
                            
                            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                            if CGImageDestinationFinalize(destination) {
                                jpegData = data as Data
                            }
                        }
                    }
                }
            }
            
            if jpegData == nil {
                let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: imageBuffer))
                jpegData = uiImage.jpegData(compressionQuality: jpegCompressionQuality)
            }
            
            if let data = jpegData {
                webSocketClient.sendFrame(data: data)
            }
        }
    }
}
