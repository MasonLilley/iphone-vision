import Foundation

class WebSocketClient {
    var webSocketTask: URLSessionWebSocketTask?
    var url: URL?
    var isConnected = false
    var pingTimer: DispatchWorkItem?

    init(url: URL? = URL(string: "ws://192.168.0.139:6789")) {
        updateURL(to: url)
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
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { error in
            if error != nil {
                // print("Error sending a message: \(error.localizedDescription)")
            }
        }
    }

    private func listen() {
        webSocketTask?.receive { result in
            switch result {
            case .failure(let error):
                print("Error receiving message: \(error.localizedDescription)")
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
                } else {
                    print("Ping sent successfully.")
                    self?.isConnected = true
                }
                
                self?.ping()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: pingTimer!)
    }


    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
    
    func updateURL(to newURL: URL?) {
        pingTimer?.cancel()
        disconnect()
        self.url = newURL
        connect()
    }
}
