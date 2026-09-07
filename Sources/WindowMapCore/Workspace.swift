import Foundation

public struct Workspace: Equatable, Codable {
    public let id: UUID
    public var name: String
    public var windowIds: [UInt32]

    public init(id: UUID = UUID(), name: String, windowIds: [UInt32] = []) {
        self.id = id; self.name = name; self.windowIds = windowIds
    }

    public var isAutoNamed: Bool { name.range(of: #"^Workspace\d+$"#, options: .regularExpression) != nil }
}
