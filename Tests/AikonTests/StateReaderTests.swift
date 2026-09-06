import Testing
@testable import Aikon
import Foundation

@Test func readsStatusFromFileName() {
    #expect(StateReader.status(fromFileName: "08ec7458-….⚠️") == .needsPermission)
    #expect(StateReader.status(fromFileName: "test-ask.❓") == .needsAnswer)
    #expect(StateReader.status(fromFileName: "a523c002-….🏁") == .finished)
    #expect(StateReader.status(fromFileName: "08ec7458-….quiet") == nil)
}

@Test func picksTheFreshestOfSeveralFiles() {
    // one session can genuinely have .⚠️, .🏁, and .quiet at the same time
    let files = [
        StateFile(uuid: "a", status: .finished,        at: Date(timeIntervalSince1970: 1788341340)),
        StateFile(uuid: "a", status: .needsPermission, at: Date(timeIntervalSince1970: 1788344428))
    ]
    #expect(StateReader.latest(files)?.status == .needsPermission)
}
