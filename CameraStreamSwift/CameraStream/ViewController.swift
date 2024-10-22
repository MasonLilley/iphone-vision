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
    public static var currentIP = "192.168.0.39"
    public static var currentPort = "6789"

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
        webSocketClient.connect()
        
        setupReconnectButton()
        setupSwapCameraButton()
        setupIPAddressButton()
        setupConnectedDisplay()
        
        connectionStatusTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateConnectionState), userInfo: nil, repeats: true)
    }
    
    func setupWebSocketClient(ip: String = currentIP, port: String = currentPort) {
            let urlString = "ws://\(ip):\(port)"
            guard let url = URL(string: urlString) else { return }
            webSocketClient = WebSocketClient(url: url)
    }
    
    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        let cameraPosition: AVCaptureDevice.Position = useSelfieCamera ? .front : .back
        
        // Attempt to get the wide-angle camera
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
        useSelfieCamera = useSelfieCamera ? false : true
        viewDidLoad()
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
        
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(getNewSendFraction))
        connectedDot.addGestureRecognizer(tapGestureRecognizer)

        view.addSubview(connectedDot)

        NSLayoutConstraint.activate([
            connectedDot.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 350),
            connectedDot.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -75),
            connectedDot.widthAnchor.constraint(equalToConstant: 30),
            connectedDot.heightAnchor.constraint(equalToConstant: 30)
        ])
        updateConnectedDot(isConnected:webSocketClient.isConnected)
    }
    
    @objc func getNewSendFraction() {
        let alert = UIAlertController(title: "Set fraction of frames NOT to send", message: "Enter fraction:", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Numerator"
            textField.text = "1"
        }
        alert.addTextField { textField in
            textField.placeholder = "Denominator"
            textField.text = "1"
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
private var sendFractionNumerator = 1
private var sendFractionDenominator = 1
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        if sendFractionNumerator == sendFractionDenominator {
            print("sending all frames")
        } else if frameCounter % sendFractionDenominator >= sendFractionDenominator - sendFractionNumerator {
            print("not sending frame!")
            return // Skip sending this frame
        }
        print("sending frame")
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
