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

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
        webSocketClient.connect()
        setupReconnectButton()
        setupIPAddressButton()
        setupConnectedDisplay()
        
        connectionStatusTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateConnectionState), userInfo: nil, repeats: true)
    }
    
    func setupWebSocketClient(ip: String = "192.168.0.113", port: String = "6789") {
            let urlString = "ws://\(ip):\(port)"
            guard let url = URL(string: urlString) else { return }
            webSocketClient = WebSocketClient(url: url)
    }
    
    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        let cameraPosition: AVCaptureDevice.Position = useSelfieCamera ? .front : .back
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {return}
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        captureSession.sessionPreset = .medium
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
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
            textField.text = "192.168.0.113"
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
        connectedDot.layer.cornerRadius = 15 //half of constraints
        view.addSubview(connectedDot)

        NSLayoutConstraint.activate([
            connectedDot.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 350),
            connectedDot.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -75),
            connectedDot.widthAnchor.constraint(equalToConstant: 30),
            connectedDot.heightAnchor.constraint(equalToConstant: 30)
        ])
        updateConnectedDot(isConnected:webSocketClient.isConnected)
    }
}



private var frameCounter = 0
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
//         if frameCounter % 3 != 0 {return} //Only send 1/3 frames

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pixelBuffer = imageBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        guard let jpegData = uiImage.jpegData(compressionQuality: 0.6) else { return }

        webSocketClient.sendFrame(data: jpegData)
    }
}
