import AST

public class AIRUnit: CustomStringConvertible {

  public init(name: String) {
    self.name = name
  }

  /// The name of the unit.
  public let name: String

  public var description: String {
    return functions.values.map(prettyPrint).sorted().joined(separator: "\n")
  }

  // MARK: Functions

  /// Create or get the existing function with the given name and type.
  public func getFunction(name: String, type: AIRFunctionType)
    -> AIRFunction
  {
    if let fn = functions[name] {
      assert(fn.type == type, "AIR function conflicts with previous declaration")
      return fn
    }

    let fn = AIRFunction(name: name, type: type)
    functions[name] = fn
    return fn
  }

  /// The functions of the unit.
  public private(set) var functions: [String: AIRFunction] = [:]

  // MARK: Types

  public func getStructType(name: String) -> AIRStructType {
    if let ty = structTypes[name] {
      return ty
    }
    let ty = AIRStructType(name: name, members: [:])
    structTypes[name] = ty
    return ty
  }

  public func getFunctionType(from domain: [AIRType], to codomain: AIRType) -> AIRFunctionType {
    if let existing = functionTypes.first(where: {
      ($0.domain == domain) && ($0.codomain == codomain)
    }) {
      return existing
    } else {
      let ty = AIRFunctionType(domain: domain, codomain: codomain)
      functionTypes.append(ty)
      return ty
    }
  }

  /// The struct types of the unit.
  public private(set) var structTypes: [String: AIRStructType] = [:]
  /// The function types of the unit.
  public private(set) var functionTypes: [AIRFunctionType] = []

}

private func prettyPrint(function: AIRFunction) -> String {
  var result = "fun $\(function.name) : \(function.type)"
  if function.blocks.isEmpty {
    return result + "\n"
  }

  result += " {\n"
  for (label, block) in function.blocks {
    result += "\(label):\n"
    for line in block.description.split(separator: "\n") {
      result += "  \(line)\n"
    }
  }
  result += "}\n"
  return result
}
