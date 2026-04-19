import Foundation

public struct DeviceToken: Sendable, Codable, Equatable {
    public let deviceId: UUID
    public let token: String

    public init(deviceId: UUID, token: String) {
        self.deviceId = deviceId
        self.token = token
    }
}
