import os

enum Log {
    static let capture = Logger(subsystem: "coops.wreckingball", category: "capture")
    static let recorder = Logger(subsystem: "coops.wreckingball", category: "recorder")
    static let app = Logger(subsystem: "coops.wreckingball", category: "app")
    static let keys = Logger(subsystem: "coops.wreckingball", category: "keys")
}
