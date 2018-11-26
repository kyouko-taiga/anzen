import AST
import Utils

public final class ConstraintCreator: ASTVisitor, SAPass {

  public init(context: ASTContext) {
    self.context = context
  }

  /// The AST context.
  public let context: ASTContext

  public func visit(_ node: PropDecl) throws {
    var propType: TypeBase? = nil
    if let annotation = node.typeAnnotation {
      propType = typeFromAnnotation(annotation: annotation)
      context.add(constraint:
        .equality(t: node.type!, u: propType!, at: .location(node, .annotation)))
    }

    if let (_, value) = node.initialBinding {
      try visit(value)
      context.add(constraint:
        .conformance(t: value.type!, u: node.type!, at: .location(node, .rvalue)))
    }
  }

  public func visit(_ node: FunDecl) throws {
    let fnType = node.type as! FunctionType

    // Determine the expected codomain of the function.
    let codomain: TypeBase
    if node.kind == .constructor {
      // If the function is a constructor, its return type must be `Self`.
      assert(node.codomain == nil)
      let selfSymbol = node.scope?.parent?.symbols["Self"]

      // Assuming constructor declarations outside of a type are caught during AST sanitizing, the
      // `Self` symbol can be expected to have been defined at this point.
      assert(selfSymbol != nil, "constructor not declared within a type")
      assert(selfSymbol?.count == 1, "overloaded 'Self' symbol")
      guard let selfMeta = selfSymbol![0].type as? Metatype
        else { fatalError("invalid 'Self' type") }
      codomain = selfMeta.type
    } else if node.codomain != nil {
      // The function has an explicit codomain annotation.
      codomain = typeFromAnnotation(annotation: node.codomain!)
    } else {
      // In the absence of explicit codomain annotation, use `Nothing`.
      codomain = NothingType.get
    }

    // Rember that methods have a type `(Self) -> (A -> B)`...
    let fnCo = node.kind == .method
      ? (fnType.codomain as! FunctionType).codomain
      : fnType.codomain
    context.add(constraint: .equality(t: fnCo, u: codomain, at: .location(node, .codomain)))

    try visit(node.parameters)
    if let body = node.body {
      try visit(body)
    }
  }

  public func visit(_ node: ParamDecl) throws {
    // Extract the type of the parameter from its annotation.
    var paramType: TypeBase? = nil
    if let annotation = node.typeAnnotation {
      paramType = typeFromAnnotation(annotation: annotation)
      context.add(constraint:
        .equality(t: node.type!, u: paramType!, at: .location(node, .annotation)))
    }

    if let value = node.defaultValue {
      try visit(value)
      context.add(constraint:
        .conformance(t: value.type!, u: node.type!, at: .location(node, .rvalue)))
    }
  }

  public func visit(_ node: BindingStmt) throws {
    try visit(node.lvalue)
    try visit(node.rvalue)
    context.add(constraint:
      .conformance(t: node.rvalue.type!, u: node.lvalue.type!, at: .location(node, .rvalue)))
  }

  public func visit(_ node: IfExpr) throws {
    try visit(node.condition)
    let bool = context.builtinTypes["Bool"]!
    context.add(constraint:
      .equality(t: node.condition.type!, u: bool, at: .location(node, .condition)))

    try visit(node.thenBlock)
    if let elseBlock = node.elseBlock {
      try visit(elseBlock)
    }

    // FIXME: Type if expression with either the type of their return statement or `Nothing`.
  }

  public func visit(_ node: BinExpr) throws {
    try visit(node.left)
    try visit(node.right)

    // Infix operators are implemented as methods of the left operand, meaning the left operand
    // should have a method `(_: R) -> T`, where:
    // - `R` is a type right right operand conforms to
    // - `T` is the codomain of the operator
    let opTy = context.getFunctionType(from: [Parameter(type: TypeVariable())], to: TypeVariable())
    node.type = opTy.codomain
    node.operatorType = opTy

    // The right operand's type must conforms to `R`.
    context.add(constraint:
      .conformance(t: node.right.type!, u: opTy.domain[0].type, at: .location(node, .binaryRHS)))

    // The left operand's type must have a method member of type `(_: R) -> T`.
    let member = node.op.rawValue
    context.add(constraint:
      .member(t: node.left.type!, member: member, u: opTy, at: .location(node, .binaryOperator)))
  }

  public func visit(_ node: CallExpr) throws {
    // Build the supposed type of the callee. Note the use of fresh variables so as to loosen
    // the constraint on the arguments.
    let domain = node.arguments.map { Parameter(label: $0.label, type: TypeVariable()) }
    let fnType = context.getFunctionType(from: domain, to: TypeVariable())
    node.type = fnType.codomain

    // Create conformance constraints for the arguments.
    let loc: ConstraintLocation = .location(node, .call)
    for (i, (argument, parameter)) in zip(node.arguments, fnType.domain).enumerated() {
      try visit(argument)
      context.add(constraint:
        .conformance(t: argument.type!, u: parameter.type, at: loc + .parameter(i)))
    }

    // The callee may represent a function or a nominal type in case it is used as a constructor.
    try visit(node.callee)
    let choices: [Constraint] = [
      .equality(t: node.callee.type!, u: fnType, at: loc),
      .construction(t: node.callee.type!, u: fnType, at: loc),
    ]
    context.add(constraint: .disjunction(choices, at: loc))
  }

  public func visit(_ node: CallArg) throws {
    try visit(node.value)
    node.type = node.value.type
  }

  public func visit(_ node: SelectExpr) throws {
    // The ownee's typed with a fresh variable, which will also be part of a membership constraint
    // contraint with the owner's type.
    node.ownee.type = TypeVariable()
    node.type = node.ownee.type

    let ownerType: TypeBase
    if let owner = node.owner {
      try visit(owner)
      ownerType = owner.type!
    } else {
      // If the select doesn't have an explicit owner, then the type of the implicit one has to be
      // the metatype of that of of the ownee. In other words, `member` should be static.
      // FIXME: Does this work, knowing that `node.type` is a type variable?
      ownerType = node.type!.metatype
    }

    context.add(constraint:
      .member(t: ownerType, member: node.ownee.name, u: node.type!, at: .location(node, .select)))
  }

  public func visit(_ node: Ident) throws {
    // Retrieve the symbol(s) associated with the identifier. If there're more than one, create a
    // disjunction constraint to model the different choices.
    guard let symbols = node.scope?.symbols[node.name] else {
      node.type = ErrorType.get
      return
    }

    // FIXME: Handle explicit generic parameters.
    assert(node.specializations.isEmpty, "bound metatypes aren't unsupported yet")

    node.type = TypeVariable()
    let choices: [Constraint] = symbols.map {
      .equality(t: node.type!, u: $0.type!, at: .location(node, .identifier))
    }
    if choices.count == 1 {
      context.add(constraint: choices[0])
    } else {
      context.add(constraint: .disjunction(choices, at: .location(node, .identifier)))
    }
  }

  public func visit(_ node: Literal<Bool>) throws {
    node.type = context.builtinTypes["Bool"]
    assert(node.type != nil)
  }

  public func visit(_ node: Literal<Int>) throws {
    node.type = context.builtinTypes["Int"]
    assert(node.type != nil)
  }

  public func visit(_ node: Literal<Double>) throws {
    node.type = context.builtinTypes["Float"]
    assert(node.type != nil)
  }

  public func visit(_ node: Literal<String>) throws {
    node.type = context.builtinTypes["String"]
    assert(node.type != nil)
  }

  private func typeFromAnnotation(annotation: Node) -> TypeBase {
    switch annotation {
    case let sign as QualSign:
      return sign.signature.map { typeFromAnnotation(annotation: $0) } ?? TypeVariable()

    case let ident as TypeIdent:
      // Type identifiers' symvols should have a metatype.
      guard let meta = ident.symbol?.type as? Metatype else {
        context.add(error: SAError.invalidTypeIdentifier(name: ident.name), on: ident)
        return ErrorType.get
      }

      if !ident.specializations.isEmpty {
        // If there are specialization arguments, we can use them to close the generic.
        guard let type = meta.type as? GenericType else {
          context.add(error: SAError.nonGenericType(type: meta.type), on: ident)
          return ErrorType.get
        }
        var bindings: [PlaceholderType: TypeBase] = [:]
        for (key, value) in ident.specializations {
          guard let placeholder = type.placeholders.first(where: { $0.name == key }) else {
            context.add(error: SAError.superfluousSpecialization(name: key), on: ident)
            return ErrorType.get
          }
          bindings[placeholder] = typeFromAnnotation(annotation: value)
        }

        let closed: TypeBase
        if let nominalType = type as? NominalType {
          closed = BoundGenericType(unboundType: nominalType, bindings: bindings)
        } else {
          assert(type is FunctionType)
          fatalError("todo")
        }

        ident.type = closed.metatype
        return closed
      }

      ident.type = meta
      return meta.type

    default:
      unreachable()
    }
  }

}
