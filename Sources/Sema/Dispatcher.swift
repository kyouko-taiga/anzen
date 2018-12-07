import AST
import Utils

/// Visitor that annotates expressions with their reified type (as inferred by the type solver), and
/// associates identifiers with their corresponding symbol.
///
/// The main purpose of this pass is to resolve identifiers' symbols, so as to know which variable,
/// function or type they refer to. The choice is based on the inferred type of the identifier,
/// which is why this pass also reifies all types.
///
/// Dispatching may fail if the pass is unable to unambiguously resolve an identifier's symbol,
/// which may happen in the presence of function declarations whose normalized (and specialized)
/// signature are found identical.
public final class Dispatcher: ASTTransformer {

  public init(context: ASTContext) {
    self.context = context
    self.solution = [:]
  }

  public init(context: ASTContext, solution: SubstitutionTable) {
    self.context = context
    self.solution = solution
  }

  /// The AST context.
  public let context: ASTContext
  /// The substitution map obtained after inference.
  public let solution: SubstitutionTable
  /// The nominal types already reified.
  private var visited: [NominalType] = []

  public func transform(_ node: ModuleDecl) throws -> Node {
    visitScopeDelimiter(node)
    return try defaultTransform(node)
  }

  public func transform(_ node: Block) throws -> Node {
    visitScopeDelimiter(node)
    return try defaultTransform(node)
  }

  public func transform(_ node: FunDecl) throws -> Node {
    visitScopeDelimiter(node)
    return try defaultTransform(node)
  }

  public func transform(_ node: TypeIdent) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: IfExpr) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: LambdaExpr) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: BinExpr) throws -> Node {
    node.type = reify(type: node.type)

    let lhs = try transform(node.left) as! Expr
    let rhs = try transform(node.right) as! Expr

    // Transform the binary expression into a function application of the form `lhs.op(rhs)`.
    let opIdent = Ident(name: node.op.rawValue, module: node.module, range: node.range)
    opIdent.scope = (lhs.type as! NominalType).memberScope
    opIdent.type = reify(type: node.operatorType)

    let callee = SelectExpr(
      owner: lhs,
      ownee: try transform(opIdent) as! Ident,
      module: node.module,
      range: node.range)
    callee.type = opIdent.type

    let arg = CallArg(value: rhs, module: node.module, range: node.range)
    arg.type = rhs.type

    let call = CallExpr(callee: callee, arguments: [arg], module: node.module, range: node.range)
    call.type = node.type

    return call
  }

  public func transform(_ node: UnExpr) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: CallExpr) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: CallArg) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: SubscriptExpr) throws -> Node {
    node.type = reify(type: node.type)
    return try defaultTransform(node)
  }

  public func transform(_ node: SelectExpr) throws -> Node {
    node.type = reify(type: node.type)
    node.owner = try node.owner.map { try transform($0) as! Expr }

    let ownerTy = node.owner != nil
      ? node.owner!.type!
      : node.type!

    // Now that the owner's type has been inferred, we can determine the scope of the ownee. Note
    // that we can expect the owner to be either a nominal type or the metatype of a nominal type,
    // as other types may not have members.
    switch ownerTy {
    case let nominal as NominalType:
      node.ownee.scope = nominal.memberScope
    case let bound as BoundGenericType:
      node.ownee.scope = (bound.unboundType as! NominalType).memberScope
    case let meta as Metatype where meta.type is NominalType:
      node.ownee.scope = (meta.type as! NominalType).memberScope!.parent
    case let meta as Metatype where meta.type is BoundGenericType:
      let unbound = (meta.type as! BoundGenericType).unboundType
      node.ownee.scope = (unbound as! NominalType).memberScope!.parent
    default:
      unreachable()
    }

    // Dispatch the symbol of the ownee, now that its scope's been determined.
    node.ownee = try transform(node.ownee) as! Ident

    return node
  }

  public func transform(_ node: Ident) throws -> Node {
    node.type = node.type.map { solution.reify(type: $0, in: context, skipping: &visited) }
    node.specializations = try Dictionary(
      uniqueKeysWithValues: node.specializations.map({ try ($0, transform($1)) }))

    assert(node.scope != nil)
    assert(node.scope!.symbols[node.name] != nil)
    var choices = node.scope!.symbols[node.name]!
    assert(!choices.isEmpty)

    // If the identifier has a function type, the actual symbol to which we'll dispatch it could be
    // in any of the accessible scopes from `node.scope`, provided those symbols are overloadable,
    // or in the member scope of a type defined in `node.scope`. Otherwise there has to be a non-
    // overloadable symbol in `node.scope`.
    if node.type is FunctionType {
      if choices[0].isOverloadable {
        // Add overloaded symbols from each accessible scope to the list of choices.
        var scope = node.scope
        while let parent = scope?.parent {
          if let symbols = parent.symbols[node.name] {
            guard symbols.first!.isOverloadable
              else { break }
            choices += symbols
          }
          scope = parent
        }
      } else {
        assert(choices.count == 1)
        guard let ty = (choices[0].type as? Metatype)?.type as? NominalType
          else { fatalError() }
        choices = ty.memberScope!.symbols["new"]!
      }

      // Filter out incompatible symbols.
      choices = choices.filter { symbol in
        let ty = symbol.isMethod
          ? (symbol.type as! FunctionType).codomain
          : symbol.type!
        var bindings: [PlaceholderType: TypeBase] = [:]
        return specializes(lhs: node.type!, rhs: ty, in: context, bindings: &bindings)
      }

      // FIXME: Disambiguise when there are several choices.
      assert(choices.count > 0)
      node.symbol = choices[0]
    } else {
      assert(choices.count == 1)
      node.symbol = choices[0]
    }

    return node
  }

  private func visitScopeDelimiter(_ node: ScopeDelimiter) {
    if let scope = node.innerScope {
      for symbol in scope.symbols.values.joined() {
        symbol.type = symbol.type.map { solution.reify(type: $0, in: context, skipping: &visited) }
      }
    }
  }

  private func reify(type: TypeBase?) -> TypeBase? {
    return type.map { solution.reify(type: $0, in: context, skipping: &visited) }
  }

}

private func specializes(
  lhs: TypeBase,
  rhs: TypeBase,
  in context: ASTContext,
  bindings: inout [PlaceholderType: TypeBase]) -> Bool
{
  switch (lhs, rhs) {
  case (_, _) where lhs == rhs:
    return true

  case (_, let right as PlaceholderType):
    if let type = bindings[right] {
      return specializes(lhs: lhs, rhs: type, in: context, bindings: &bindings)
    }
    bindings[right] = lhs
    return true

  case (let left as BoundGenericType, _):
    let closed = left.unboundType is NominalType
      ? left.unboundType
      : left.close(using: left.bindings, in: context)
    return specializes(lhs: closed, rhs: rhs, in: context, bindings: &bindings)

  case (_, let right as BoundGenericType):
    return specializes(lhs: right, rhs: lhs, in: context, bindings: &bindings)

  case (let left as Metatype, let right as Metatype):
    return specializes(lhs: left.type, rhs: right.type, in: context, bindings: &bindings)

  case (let left as FunctionType, let right as FunctionType):
    if left.placeholders.isEmpty && right.placeholders.isEmpty {
      return left == right
    }

    guard left.domain.count == right.domain.count
      else { return false }
    for params in zip(left.domain, right.domain) {
      guard params.0.label == params.1.label
        else { return false }
      guard specializes(lhs: params.0.type, rhs: params.1.type, in: context, bindings: &bindings)
        else { return false }
    }
    return specializes(lhs: left.codomain, rhs: right.codomain, in: context, bindings: &bindings)

  case (is TypeVariable, _), (_, is TypeVariable):
    preconditionFailure("Unexpected type variable, did you forget to reify?")

  default:
    return false
  }
}
