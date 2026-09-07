import Testing
@testable import Aikon
import SwiftUI

// The menu bar label is measured to set the status item's width, and the first
// version measured a view that had already been stretched to the width being
// computed — so the answer came back one digit short and the last number was
// clipped on screen. These pin the property that measurement has to have:
// more digits must ask for more room.

@MainActor
private func width(_ counts: Counts) -> CGFloat {
    let renderer = ImageRenderer(content: StatusItemLabel(counts: counts))
    renderer.scale = 1
    return renderer.nsImage?.size.width ?? 0
}

@Test @MainActor
func theLabelAsksForRoomAtAll() {
    #expect(width(Counts(waiting: 0, done: 0, busy: 0)) > 0)
}

@Test @MainActor
func aSecondDigitMakesTheLabelWider() {
    let single = width(Counts(waiting: 9, done: 9, busy: 9))
    let double = width(Counts(waiting: 12, done: 34, busy: 56))
    #expect(double > single)
}

@Test @MainActor
func everyExtraDigitKeepsAddingRoom() {
    let two = width(Counts(waiting: 12, done: 34, busy: 56))
    let three = width(Counts(waiting: 123, done: 456, busy: 789))
    #expect(three > two)
}

@Test @MainActor
func digitsAreTabularSoTheWidthDoesNotDependOnWhichOnesTheyAre() {
    // Monospaced digits are what stops the label twitching in the menu bar
    // every time a count ticks from 1 to 8.
    let ones = width(Counts(waiting: 11, done: 11, busy: 11))
    let eights = width(Counts(waiting: 88, done: 88, busy: 88))
    #expect(abs(ones - eights) < 0.5)
}
