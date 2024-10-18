import Foundation

class WebSocketClient {
    var webSocketTask: URLSessionWebSocketTask?
    var url: URL?
    var isConnected = false

    init(url: URL? = URL(string: "ws://192.168.0.113:6789")) {
        self.url = url
    }

    func connect() {
        guard let url = url else { return }
        print("Connecting to \(url)")
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true // Set connected state to true
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
        webSocketTask?.sendPing { error in
            if let error = error {
                print("Ping error: \(error.localizedDescription)")
                self.isConnected = false
            } else {
                print("Ping sent successfully.")
                self.isConnected = true
            }
            
            // Schedule the next ping after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.ping()
            }
        }
    }


    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}
