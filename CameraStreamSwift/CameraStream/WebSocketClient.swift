import Foundation

class WebSocketClient {
    var webSocketTask: URLSessionWebSocketTask?
    var url: URL?
    var isConnected = false
    var pingTimer: DispatchWorkItem?
    var currentIP = ViewController.currentIP
    
    // backpressure detection
    private var messageQueue = 0
    private let maxQueueSize = 5
    var isBackpressured: Bool {
        return messageQueue >= maxQueueSize
    }
    var onBackpressureCallback: ((Double) -> Void)?
    private var lastSentTime: CFAbsoluteTime?

    init(url: URL? = nil) {
        if let customURL = url {
            updateURL(to: customURL)
        } else if let defaultURL = URL(string: addWebSocketScheme(to: currentIP)) {
            updateURL(to: defaultURL)
        }
    }

    func connect() {
        guard let url = url else { return }
        print("Connecting to \(url)")
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        if webSocketTask == nil {
            print("no websocket task!")
        }
        webSocketTask?.resume()
        listen()
        ping()
    }

    func sendFrame(data: Data) {
        messageQueue += 1
        lastSentTime = CFAbsoluteTimeGetCurrent()
        
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            guard let self = self else { return }
            
            self.messageQueue = max(0, self.messageQueue - 1)
            
            let pressure = Double(self.messageQueue) / Double(self.maxQueueSize)
            self.onBackpressureCallback?(pressure)
            
            if let error = error {
                print("Error sending a message: \(error.localizedDescription)")
            } else if let lastTime = self.lastSentTime {
                let latency = CFAbsoluteTimeGetCurrent() - lastTime
                if latency > 0.1 { // >100ms == network lag
                    let calculatedPressure = min(1.0, latency / 0.5) // 500ms = full pressure
                    self.onBackpressureCallback?(calculatedPressure)
                }
            }
        }
        
        if messageQueue >= maxQueueSize / 2 {
            onBackpressureCallback?(Double(messageQueue) / Double(maxQueueSize))
        }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                print("Error receiving message: \(error.localizedDescription)")
                self.onBackpressureCallback?(1.0)
            case .success(let message):
                switch message {
                case .data(let data):
                    print("Received data: \(data.count) bytes")
                case .string(let text):
                    print("Received string: \(text)")
                default:
                    break
                }
                self.listen()
            }
        }
    }
    
    private func ping() {
        pingTimer?.cancel()
        
        pingTimer = DispatchWorkItem { [weak self] in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    print("Ping error: \(error.localizedDescription)")
                    self?.isConnected = false
                    self?.onBackpressureCallback?(1.0)
                } else {
                    print("Ping sent successfully.")
                    self?.isConnected = true
                    if self?.isBackpressured == false {
                        self?.onBackpressureCallback?(0.0)
                    }
                }
                
                self?.ping()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: pingTimer!)
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        messageQueue = 0
    }
    
    func updateURL(to newURL: URL?) {
        pingTimer?.cancel()
        disconnect()
        self.url = newURL
        connect()
    }
    
    private func addWebSocketScheme(to ip: String) -> String {
        if ip.hasPrefix("ws://") || ip.hasPrefix("wss://") {
            return ip
        }
        // Default to `ws://` if no scheme is provided
        return "ws://\(ip)"
    }
}
