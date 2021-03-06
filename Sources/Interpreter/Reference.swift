import AnzenIR
import AST
import Utils

/// A reference to a value container.
///
/// At runtime, all AIR registers are bound to references, which are pointers to value containers.
/// In C's parlance, a reference is a pointer to a pointer to some value. This additional level of
/// indirections enables the support of AIR's different assignment semantics, and gives the
/// opportunity to attach runtime capabilities to each reference.
///
/// Note that reference identity is actually computed on the referred value containers, as those
/// actually represent the values being manipulated.
final class Reference: CustomStringConvertible {

  /// The value pointer to which this reference refers.
  ///
  /// If this property is `nil`, the reference is said to be `null`.
  var pointer: ValuePointer?

  /// The type of the pointed value.
  ///
  /// - Note:
  ///   Because of polymorphism, the type of the reference is not necessarily identical to referred
  ///   value's type. It is however guaranteed to be a supertype thereof.
  let type: AIRType

  /// This reference's memory state.
  var state: MemoryState

  init(to pointer: ValuePointer?, type: AIRType, state: MemoryState) {
    self.pointer = pointer
    self.type = type
    self.state = state
  }

  convenience init(type: AIRType) {
    self.init(to: nil, type: type, state: .uninitialized)
  }

  deinit {
    if case .borrowed(let owner) = state, owner != nil {
      guard case .shared(let count) = owner!.state else { unreachable() }
      owner!.state = count > 1
        ? .shared(count: count - 1)
        : .unique
    }
  }

  var description: String {
    if let pointer = self.pointer {
      return withUnsafePointer(to: pointer) {
        "Reference(to: \(pointer) @ \($0)"
      }
    } else {
      return "null"
    }
  }

  // MARK: Capabilities helpers

  func assertReadable(debugInfo: DebugInfo?) throws {
    let range = debugInfo?[.range] as? SourceRange
    switch state {
    case .uninitialized:
      throw MemoryError("illegal access to uninitialized reference", at: range)
    case .moved:
      throw MemoryError("illegal access to moved reference", at: range)
    default:
      break
    }
  }

}
