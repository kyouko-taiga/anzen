public class StructType: SemanticType {

    public init(
        name        : String,
        placeholders: Set<String> = [],
        properties  : [String: QualifiedType] = [:],
        methods     : [String: [SemanticType]] = [:])
    {
        self.name         = name
        self.placeholders = placeholders
        self.properties   = properties
        self.methods      = methods
    }

    public let name        : String
    public let placeholders: Set<String>
    public var properties  : [String: QualifiedType]
    public var methods     : [String: [SemanticType]]

    public var isGeneric: Bool {
        return !self.placeholders.isEmpty
            || self.properties.values.contains(where: { $0.type.isGeneric })
            || self.methods   .values.contains(where: { $0.contains(where: { $0.isGeneric }) })
    }

    public func equals(to other: SemanticType) -> Bool {
        guard let rhs = other as? StructType else { return false }
        return self === rhs
    }

}
