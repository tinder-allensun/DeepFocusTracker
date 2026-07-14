import Foundation

/// How time spent in an application counts toward a focus block.
enum FocusCategory: String, Codable, CaseIterable, Identifiable {
    case focus
    case neutral
    case distraction

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .neutral: return "Neutral"
        case .distraction: return "Distraction"
        }
    }
}
