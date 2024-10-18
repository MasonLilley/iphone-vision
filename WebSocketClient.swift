import Foundation

class WebSocketClient {
    var webSocketTask: URLSessionWebSocketTask?

    let url = URL(string: "ws://192.168.0.113:6789")! // Change to 'wss' if using a secure WebSocket

    func connect() {
        print("Connecting to \(url)")
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        listen() // Start listening for messages
    }

    func sendFrame(data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { error in
            if let error = error {
//                print("Error sending a message: \(error.localizedDescription)")
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
                    1+1
                    //print("Received string: \(text)")
                default:
                    break
                }
                // Listen for the next message
                self.listen()
            }
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}
