import Testing
import Combine
@testable import Aikon

// Why `StatusBarController` takes the counts from the publisher instead of
// reading `model.counts` inside the sink.
//
// `@Published` announces a change before the property holds the new value, so
// a subscriber that reaches back for the model reads the *previous* one. That
// is how the menu bar label came to be measured against the old numbers: a
// count crossing from one digit to two was drawn in a box sized for one, and
// the second digit was cut off. This pins the behaviour the fix depends on, so
// nobody "simplifies" it back.

@MainActor
private final class Subject: ObservableObject {
    @Published var value = 0
}

@Test @MainActor
func aPublishedSinkSeesTheNewValueOnlyThroughItsArgument() {
    let subject = Subject()
    var fromArgument: [Int] = []
    var readBackFromTheObject: [Int] = []

    let token = subject.$value.sink { incoming in
        fromArgument.append(incoming)
        readBackFromTheObject.append(subject.value)
    }
    defer { token.cancel() }

    subject.value = 7
    subject.value = 42

    // The subscriber is called once on subscription, then per change.
    #expect(fromArgument == [0, 7, 42])
    // Reading the object back gives what it held *before* each change: this is
    // the trap, and the reason the label is measured from the argument.
    #expect(readBackFromTheObject == [0, 0, 7])
}
