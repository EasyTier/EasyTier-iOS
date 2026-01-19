import Foundation

struct TextItem: Identifiable, Equatable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    var id = UUID()
    var text: String
    
    var description: String { text }
    
    init(_ text: String) {
        self.text = text
    }
    
    init(stringLiteral text: String) {
        self.text = text
    }
}

struct IdenticalTextItem: Identifiable, Equatable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    var id: String { self.text }
    var text: String
    
    var description: String { text }
    
    init(_ text: String) {
        self.text = text
    }
    
    init(stringLiteral text: String) {
        self.text = text
    }
}
