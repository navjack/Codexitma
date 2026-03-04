import Foundation

#if canImport(Combine)
import Combine
typealias EditorObservableObject = ObservableObject
typealias EditorPublished<Value> = Published<Value>
#else
protocol EditorObservableObject: AnyObject {}

@propertyWrapper
struct EditorPublished<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif
