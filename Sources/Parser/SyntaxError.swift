import AST

/// A syntax error.
///
/// A syntax error is an error that occurs when trying to parse syntactically invalid code.
public enum SyntaxError {

  /// Occurs when the operand of a cast operation is a non-parenthesized infix expression.
  case ambiguousCastOperand
  /// Occurs when parsing specialization lists with duplicate generic parameter names.
  case duplicateGenericParameter(key: String)
  /// Occurs when the parser fails to parse the member of a select expression.
  case expectedMember
  /// Occurs when the parser fails to parse a list separator.
  case expectedSeparator(separator: String)
  /// Occurs when the parser fails to parse a statement delimiter.
  case expectedStatementDelimiter
  /// Occurs when the parser encounters an invalid compiler directive.
  case invalidDirective(directive: Directive)
  /// Occurs when the parses encounters an invalid type qualifier.
  case invalidQualifier(value: String)
  /// Occurs when the parser encounters a non-declaration node at the top-level.
  case invalidTopLevelDeclaration(node: ASTNode)
  /// Occurs when the parser encounters a reserved keyword while parsing an identifier.
  case keywordAsIdentifier(keyword: String)
  /// Occurs when the parser encounters non-associative adjacent infix operators.
  case nonAssociativeOperator(op: String)
  /// Occurs when the parser unexpectedly depletes the stream.
  case unexpectedEOF
  /// Occurs when the parser encounters an unexpected syntactic construction.
  case unexpectedConstruction(expected: String?, got: ASTNode)
  /// Occurs when the parser encounters an unexpected token.
  case unexpectedToken(expected: String?, got: Token)

}

extension SyntaxError: CustomStringConvertible {

  public var description: String {
    switch self {
    case .ambiguousCastOperand:
      return "ambiguous cast expression, infix expressions should be parenthesized"

    case .duplicateGenericParameter(let key):
      return "duplicate generic parameter name '\(key)'"

    case .expectedMember:
      return "expected member name following '.'"

    case .expectedSeparator(let separator):
      return "consecutive elements should be separated by '\(separator)'"

    case .expectedStatementDelimiter:
      return "consecutive statements should be separated by ';'"

    case .invalidDirective(let directive):
      return "invalid compiler directive '\(directive.name)'"

    case .invalidQualifier(let value):
      return "invalid qualifier '\(value)'"

    case .invalidTopLevelDeclaration(let node):
      switch node {
      case is Stmt, is Expr:
        return "top-level expressions are allowed only in main files"
      default:
        return "invalid top-level node '\(node)'"
      }

    case .keywordAsIdentifier(let keyword):
      return "keyword '\(keyword)' cannot be used as an identifier"

    case .nonAssociativeOperator(let op):
      return "use of adjacent non-associative operators '\(op)'"

    case .unexpectedEOF:
      return "unexpected end of stream"

    case .unexpectedConstruction(let expected, let found):
      if expected != nil {
        return "expected \(expected!), found \(found)"
      } else {
        return "unexpected \(found)"
      }

    case .unexpectedToken(let expected, let found):
      if expected != nil {
        return found.kind != .newline
          ? "expected \(expected!), found '\(found)'"
          : "expected \(expected!)"
      } else {
        return "unexpected token '\(found)'"
      }
    }
  }

}
