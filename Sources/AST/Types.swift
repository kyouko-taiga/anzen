/// A type qualifier set.
public struct TypeQualSet: OptionSet, Hashable {

  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let cst = TypeQualSet(rawValue: 1 << 0)
  public static let mut = TypeQualSet(rawValue: 1 << 1)

}

/// A type object
public class TypeBase: Hashable {

  /// The compiler context.
  public unowned let context: CompilerContext

  /// The type's qualifiers.
  public let quals: TypeQualSet

  /// The type's kind.
  public var kind: TypeKind { return context.getTypeKind(of: self) }

  /// Returns the set of unbound generic placeholders occuring in the type.
  public func getUnboundPlaceholders() -> Set<TypePlaceholder> {
    return []
  }

  internal init(quals: TypeQualSet, context: CompilerContext) {
    self.quals = quals
    self.context = context
  }

  public static func == (lhs: TypeBase, rhs: TypeBase) -> Bool {
    return lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    let oid = ObjectIdentifier(self)
    hasher.combine(oid)
  }

  /// Returns whether two types are structurally equal, as opposed to identity equivalence.
  ///
  /// This method is intended to be overriden by type subclasses and used internally to guarantee
  /// instances' uniqueness throughout all compilation stages.
  internal func equals(to other: TypeBase) -> Bool {
    return self === other
  }

  /// Returns this type's structural hash.
  ///
  /// This method is intended to be overriden by type subclasses and used internally to compute the
  /// type hash values based on their structures rather than on their identity.
  internal func hashContents(into hasher: inout Hasher) {
    hash(into: &hasher)
  }

  /// Accepts a type transformer.
  public func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    fatalError("call to abstract method 'accept(transformer:)'")
  }

}

/// A kind.
///
/// A kind (a.k.a. metatype) refers to the type of a type.
public final class TypeKind: TypeBase {

  /// The type constructed by this kind.
  public let type: TypeBase

  public override func getUnboundPlaceholders() -> Set<TypePlaceholder> {
    return type.getUnboundPlaceholders()
  }

  internal init(of type: TypeBase, in context: CompilerContext) {
    self.type = type
    super.init(quals: [], context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? TypeKind
      else { return false }
    return (self.quals == rhs.quals)
        && (self.type === rhs.type)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

/// A type variable used during type inference.
public final class TypeVar: TypeBase {
}

/// A type placeholder in a generic type.
public final class TypePlaceholder: TypeBase {

  /// The placeholder's decl.
  public unowned let decl: GenericParamDecl

  public override func getUnboundPlaceholders() -> Set<TypePlaceholder> {
    return Set([self])
  }

  internal init(quals: TypeQualSet, decl: GenericParamDecl, in context: CompilerContext) {
    self.decl = decl
    super.init(quals: quals, context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? TypePlaceholder else { return false }
    return (self.quals == rhs.quals)
        && (self.decl === rhs.decl)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

/// A type whose generic parameters have been (possibly partially) bound.
public final class BoundGenericType: TypeBase {

  /// The type with unbound generic parameters.
  public let type: TypeBase

  /// The generic parameters' assignments.
  public let bindings: [TypePlaceholder: TypeBase]

  public override func getUnboundPlaceholders() -> Set<TypePlaceholder> {
    return type.getUnboundPlaceholders().subtracting(bindings.keys)
  }

  internal init(
    type: TypeBase,
    bindings: [TypePlaceholder: TypeBase],
    in context: CompilerContext)
  {
    self.type = type
    self.bindings = bindings
    super.init(quals: type.quals, context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? BoundGenericType else { return false }
    return (self.quals == rhs.quals)
        && (self.type === rhs.type)
        && (self.bindings == rhs.bindings)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

public final class FunType: TypeBase {

  /// A function type's parameter.
  public struct Param: Equatable {

    /// The parameter's label.
    public let label: String?

    /// The parameter's type.
    public let type: TypeBase

    public init(label: String? = nil, type: TypeBase) {
      self.label = label
      self.type = type
    }

  }

  /// The function's generic paramters.
  public var genericParams: [TypePlaceholder]

  /// The function's domain.
  public var dom: [Param]

  /// The function's codomain
  public var codom: TypeBase

  public override func getUnboundPlaceholders() -> Set<TypePlaceholder> {
    return Set(genericParams)
  }

  internal init(
    quals: TypeQualSet,
    genericParams: [TypePlaceholder],
    dom: [Param],
    codom: TypeBase,
    in context: CompilerContext)
  {
    self.genericParams = genericParams
    self.dom = dom
    self.codom = codom
    super.init(quals: quals, context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? FunType
      else { return false }
    return (self.quals == rhs.quals)
        && (self.genericParams == rhs.genericParams)
        && (self.dom == rhs.dom)
        && (self.codom == rhs.codom)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

public class NominalType: TypeBase {

  /// The type's decl.
  public unowned let decl: NominalTypeDecl

  /// The types's generic parameters.
  public var genericParams: [TypePlaceholder] {
    return decl.genericParams.map { $0.type as! TypePlaceholder }
  }

  public override func getUnboundPlaceholders() -> Set<TypePlaceholder> {
    return Set(genericParams)
  }

  fileprivate init(quals: TypeQualSet, decl: NominalTypeDecl, context: CompilerContext) {
    self.decl = decl
    super.init(quals: quals, context: context)
  }

}

public final class InterfaceType: NominalType {

  internal init(quals: TypeQualSet, decl: InterfaceDecl, in context: CompilerContext) {
    super.init(quals: quals, decl: decl, context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? InterfaceType
      else { return false }
    return (self.quals == rhs.quals)
      && (self.decl === rhs.decl)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

public final class StructType: NominalType {

  internal init(quals: TypeQualSet, decl: StructDecl, in context: CompilerContext) {
    super.init(quals: quals, decl: decl, context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? StructType
      else { return false }
    return (self.quals == rhs.quals)
        && (self.decl === rhs.decl)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

public final class UnionType: NominalType {

  internal init(quals: TypeQualSet, decl: UnionDecl, in context: CompilerContext) {
    super.init(quals: quals, decl: decl, context: context)
  }

  internal override func equals(to other: TypeBase) -> Bool {
    guard let rhs = other as? UnionType else { return false }
    return (self.quals == rhs.quals)
        && (self.decl === rhs.decl)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

// MARK: - Built-ins

/// A built-in type.
public final class BuiltinType: TypeBase {

  /// The type's name.
  public let name: String

  public init(name: String, context: CompilerContext) {
    self.name = name
    super.init(quals: [], context: context)
  }

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}

/// The type of invalid expressions and signatures.
public final class ErrorType: TypeBase {

  public override func accept<T>(transformer: T) -> T.Result where T: TypeTransformer {
    return transformer.transform(self)
  }

}
