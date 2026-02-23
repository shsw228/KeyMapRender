import Foundation

protocol DependencyClient: Sendable {
    static var liveValue: Self { get }
    static var testValue: Self { get }
}

func testDependency<D: DependencyClient>(of type: D.Type, injection: (inout D) -> Void) -> D {
    var dependency = type.testValue
    injection(&dependency)
    return dependency
}
