public enum FunctionAttribute {

    case mutable
    case `static`

}

public class FunctionType: SemanticType {

    public typealias ParameterDescription = (label: String?, type: QualifiedType)

    public init(
        placeholders: Set<String> = [],
        from domain : [ParameterDescription],
        to codomain : QualifiedType)
    {
        self.placeholders = placeholders
        self.domain       = domain
        self.codomain     = codomain
    }

    public let placeholders: Set<String>
    public let domain      : [ParameterDescription]
    public var codomain    : QualifiedType

    public var isGeneric: Bool {
        return !self.placeholders.isEmpty
    }

    public func equals(to other: SemanticType) -> Bool {
        guard let rhs = other as? FunctionType else { return false }
        return self.placeholders == rhs.placeholders
            && self.domain       == rhs.domain
            && self.codomain     == rhs.codomain
    }

    /// Returns the bounded version of the function.
    public var bounded: FunctionType {
        precondition(self.domain.count > 0)
        return FunctionType(from: Array(self.domain.dropFirst()), to: self.codomain)
    }

}

// MARK: Internals

func ==(
    lhs: [FunctionType.ParameterDescription], rhs: [FunctionType.ParameterDescription]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (lp, rp) in zip(lhs, rhs) {
        guard lp.label == rp.label && lp.type == rp.type else { return false }
    }
    return true
}
