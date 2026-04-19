import Foundation
import OSLog

public enum Log {
    public static let subsystem = "com.yourco.fastshared"
    public static let upload = Logger(subsystem: subsystem, category: "upload")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let share = Logger(subsystem: subsystem, category: "share")
}
