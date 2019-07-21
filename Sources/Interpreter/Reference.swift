import AnzenIR

/// A reference to a value container.
///
/// At runtime, all AIR registers are bound to references, which are pointers to value containers.
/// In C's parlance, a reference is a pointer to a pointer to some value. This additional level of
/// indirections enables the support of AIR's different assignment semantics, and gives the
/// opportunity to attach runtime capabilities to each reference.
///
/// Note that reference identity is actually computed on the referred value containers, as those
/// actually represent the values being manipulated.
class Reference: CustomStringConvertible {

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

  /// This reference's typestate capability.
  var state: ReferenceState

  init(to pointer: ValuePointer?, type: AIRType, state: ReferenceState) {
    self.pointer = pointer
    self.type = type
    self.state = state
  }

//  convenience init(to pointer: ValuePointer, type: AIRType) {
//    self.init(to: pointer, type: type, state: .unique)
//  }

  convenience init(type: AIRType) {
    self.init(to: nil, type: type, state: .uninitialized)
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

}

/// The owning reference for all static objects.
class StaticReference: Reference {

  override var state: ReferenceState {
    get { return .shared(count: Int.max) }
    set { }
  }

  private init() {
    super.init(to: nil, type: .anything, state: .shared(count: Int.max))
  }

  public static let get = StaticReference()

}
