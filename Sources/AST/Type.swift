import Utils

/// Base class for all types in Anzen.
public class TypeBase: Equatable {

  fileprivate init() {}

  /// The metatype of the type.
  public lazy var metatype: Metatype = { [unowned self] in
    return Metatype(of: self)
  }()

  /// Returns whether this type is a subtype of another.
  public func isSubtype(of other: TypeBase) -> Bool {
    return (self != other) && (other == TypeBase.anything)
  }

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    fatalError("can't open abstract type \(type(of: self))")
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  public func close(
    using bindings: [PlaceholderType: TypeBase],
    in context: ASTContext) -> TypeBase
  {
    fatalError("can't close abstract type \(type(of: self))")
  }

  public static func == (lhs: TypeBase, rhs: TypeBase) -> Bool {
    return lhs === rhs
  }

  /// The built-in `Anything` type, which represents the top of the lattice.
  public static let anything = StructType(name: "Anything")
  /// The built-in `Nothing` type, which represents the bottom of the lattice.
  public static let nothing = StructType(name: "Nothing")

}

/// Class to represent the description of a type.
public final class Metatype: TypeBase, CustomStringConvertible {

  fileprivate init(of type: TypeBase) {
    self.type = type
  }

  public let type: TypeBase

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    return type.open(using: bindings, in: context).metatype
  }

  public var description: String {
    return "\(type).metatype"
  }

}

/// A special type that's used to represent a typing failure.
public final class ErrorType: TypeBase, CustomStringConvertible {

  public static let get = ErrorType()

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    return self
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  public override func close(
    using bindings: [PlaceholderType: TypeBase] = [:],
    in context: ASTContext) -> TypeBase
  {
    return self
  }

  public var description: String {
    return "<error type>"
  }

}

/// A type variable used during type checking.
public final class TypeVariable: TypeBase, Hashable, CustomStringConvertible {

  public override init() {
    self.id = TypeVariable.nextID
    TypeVariable.nextID += 1
  }

  public let id: Int
  private static var nextID = 0

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    return BoundGenericType(unboundType: self, bindings: bindings)
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  public override func close(
    using bindings: [PlaceholderType: TypeBase] = [:],
    in context: ASTContext) -> TypeBase
  {
    return self
  }

  public var hashValue: Int {
    return id
  }

  public var description: String {
    return "$\(id)"
  }

}

/// Protocol for types that may have generic placeholders.
public protocol GenericType {

  /// The type placeholders of the generic type.
  var placeholders: [PlaceholderType] { get }

}

/// Class to represent a possibly incomplete type whose placeholders have been fixed.
public final class BoundGenericType: TypeBase, CustomStringConvertible {

  public init(unboundType: TypeBase, bindings: [PlaceholderType: TypeBase]) {
    self.unboundType = unboundType
    self.bindings = bindings
  }

  /// The generic type with unbound placeholders.
  public let unboundType: TypeBase
  /// The unbound placeholder assignments.
  public let bindings: [PlaceholderType: TypeBase]

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    let updatedBindings = Dictionary(
      uniqueKeysWithValues: self.bindings.map({ (key, value) in
        (key, (value as? PlaceholderType).flatMap({ bindings[$0] }) ?? value)
      }))
    return BoundGenericType(unboundType: unboundType, bindings: updatedBindings)
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  public override func close(
    using bindings: [PlaceholderType: TypeBase] = [:],
    in context: ASTContext) -> TypeBase
  {
    let updatedBindings = Dictionary(
      uniqueKeysWithValues: self.bindings.map({ (key, value) in
        (key, (value as? PlaceholderType).flatMap({ bindings[$0] }) ?? value)
      }))
    return unboundType.close(using: updatedBindings, in: context)
  }

  public var description: String {
    let placeholders = bindings.map({ "\($0.key)=\($0.value)" }).joined(separator: ", ")
    return "<\(placeholders)>\(unboundType)"
  }

}

/// Class to represent types whose name can be use to distinguish structurally-similar types.
public class NominalType: TypeBase, GenericType, Hashable, CustomStringConvertible {

  public required init(name: String) {
    self.name = name
  }

  /// The name of the type.
  public let name: String
  /// The type placeholders of the type, in case the type's generic.
  public var placeholders: [PlaceholderType] = []
  /// The members of the type.
  public var members: [String: [TypeBase]] = [:]

  /// Returns whether this type is a subtype of another.
  public override func isSubtype(of other: TypeBase) -> Bool {
    // FIXME: Handle interface conformance.
    return (self != other) && (other == TypeBase.anything)
  }

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    // FIXME: Can we reach this path?
    assertionFailure("unreachable")

    // Make sure the type needs to be open.
    guard !placeholders.isEmpty
      else { return self }

    // Notice that nominal types aren't opened recursively. Instead, we simply store what fresh
    // variables placeholders should be bound to.
    let updatedBindings = bindings.merging(
      placeholders.map { (key: $0, value: TypeVariable()) },
      uniquingKeysWith: { lhs, _ in lhs })
    return OpenedNominalType(unboundType: self, bindings: updatedBindings)
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  ///
  /// - Remark: We intentionally don't reify bound nominal types, so as to preserve the parameters
  ///   with which they should be bound.
  public override func close(
    using bindings: [PlaceholderType: TypeBase] = [:],
    in context: ASTContext) -> TypeBase
  {
    let typeBindings = bindings.filter { placeholders.contains($0.key) }
    return placeholders.isEmpty
      ? self
      : BoundGenericType(unboundType: self, bindings: typeBindings)
  }

  public var hashValue: Int {
    var h = 31 &* name.hashValue
    for ph in placeholders {
      h = 31 &* h &+ ph.hashValue
    }
    return h
  }

  public var description: String {
    return !placeholders.isEmpty
      ? name + "<" + placeholders.map({ $0.name }).joined(separator: ", ") + ">"
      : name
  }

}

/// A type placeholder, a.k.a. a generic parameter.
public final class PlaceholderType: NominalType {

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    return bindings[self] ?? self
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  public override func close(
    using bindings: [PlaceholderType: TypeBase] = [:],
    in context: ASTContext) -> TypeBase
  {
    assert(bindings.keys.contains(self), "partial specializations aren't supported yet")
    return bindings[self]!
  }

}

/// A struct type.
public final class StructType: NominalType {}

/// Class to represent a opened nominal generic type that hasn't been been closed yet.
public final class OpenedNominalType: TypeBase, CustomStringConvertible {

  public init(unboundType: NominalType, bindings: [PlaceholderType: TypeVariable]) {
    self.unboundType = unboundType
    self.bindings = bindings
  }

  /// The generic type with unbound placeholders.
  public let unboundType: NominalType
  /// The fresh variables used for which placeholders are substituted.
  public let bindings: [PlaceholderType: TypeVariable]

  public var description: String {
    return "opened(\(unboundType))"
  }

}

/// Class to represent function types.
public final class FunctionType: TypeBase, GenericType, CustomStringConvertible {

  internal init(domain: [Parameter], codomain: TypeBase, placeholders: [PlaceholderType]) {
    self.domain = domain
    self.codomain = codomain
    self.placeholders = placeholders
  }

  /// The domain of the function.
  public let domain: [Parameter]
  /// The codomain of the function.
  public let codomain: TypeBase
  /// The type placeholders of the type, in case the type's generic.
  public let placeholders: [PlaceholderType]

  /// Returns whether this type is a subtype of another.
  public override func isSubtype(of other: TypeBase) -> Bool {
    guard let rhs = other as? FunctionType else {
      return other == TypeBase.anything
    }

    guard domain.count == rhs.domain.count else { return false }
    for (pl, pr) in zip(domain, rhs.domain) {
      guard pl.type.isSubtype(of: pr.type) && pl.label == pr.label else { return false }
    }
    return codomain.isSubtype(of: rhs.codomain)
  }

  /// Opens the type, replacing occurences of placeholders with fresh variables.
  public override func open(
    using bindings: [PlaceholderType: TypeVariable] = [:],
    in context: ASTContext) -> TypeBase
  {
    // Make sure the type needs to be open.
    guard !placeholders.isEmpty
      else { return self }

    // As functions do not need to retain which types their placeholders were bound to, opening one
    // amounts to create a new monomorphic version where placeholder are substituted.
    let updatedBindings = bindings.merging(
      placeholders.map { (key: $0, value: TypeVariable()) },
      uniquingKeysWith: { lhs, _ in lhs })
    return context.getFunctionType(
      from: domain.map({
        Parameter(label: $0.label, type: $0.type.open(using: updatedBindings, in: context))
      }),
      to: codomain.open(using: updatedBindings, in: context))
  }

  /// Closes the type, effectively replacing its placeholders with their given substitution.
  public override func close(
    using bindings: [PlaceholderType: TypeBase] = [:],
    in context: ASTContext) -> TypeBase
  {
    let domain = self.domain.map {
      Parameter(label: $0.label, type: $0.type.close(using: bindings, in: context))
    }
    let codomain = self.codomain.close(using: bindings, in: context)
    return context.getFunctionType(from: domain, to: codomain)
  }

  public var description: String {
    let params = domain.map({ $0.description }).joined(separator: ", ")
    return !placeholders.isEmpty
      ? "<" + placeholders.map({ $0.name }).joined(separator: ", ") + "> (\(params)) -> \(codomain)"
      : "(\(params)) -> \(codomain)"
  }

}

/// A function parameter.
public struct Parameter: Equatable, CustomStringConvertible {

  public init(label: String?, type: TypeBase) {
    self.label = label
    self.type = type
  }

  public let label: String?
  public let type: TypeBase

  public var description: String {
    return "\(label ?? "_"): \(type)"
  }

  public static func == (lhs: Parameter, rhs: Parameter) -> Bool {
    return (lhs.label == rhs.label) && (lhs.type == rhs.type)
  }

}
