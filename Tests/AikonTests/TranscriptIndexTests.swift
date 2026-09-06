import Testing
@testable import Aikon
import Foundation

/// A 128 KB tail almost always starts mid-way through a multibyte character.
/// Strict decoding used to return nil for the WHOLE chunk, so the panel couldn't
/// read the status and showed "working". On a real machine this broke 6 out of
/// 142 transcripts.
private func truncatedChunk(_ text: String) -> Data {
    var data = Data("café".utf8)        // tail end of the previous line
    data.removeLast()                   // cut the last (multibyte) character in half
    data.append(Data(("\n" + text).utf8))
    return data
}

@Test @MainActor func truncatedTailStillReads() {
    let line = #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#
    #expect(TranscriptIndex.working(inTail: truncatedChunk(line)) == false)

    let busy = #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#
    #expect(TranscriptIndex.working(inTail: truncatedChunk(busy)) == true)
}

@Test @MainActor func truncatedFileStartStillGivesAPath() {
    let line = #"{"type":"user","cwd":"/Users/example/Projects/alpha"}"#
    #expect(TranscriptIndex.findCWD(in: truncatedChunk(line)) == "/Users/example/Projects/alpha")
}

@Test @MainActor func toolResultCountsAsWork() {
    let line = #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#
    #expect(TranscriptIndex.working(inTail: Data(line.utf8)) == true)
}

/// While Claude is still thinking about a prompt, the transcript has no Claude
/// record yet — the last entry is the prompt itself. The parser used to look
/// further back, land on the previous turn's `end_turn`, and the panel wrote
/// "finished" while work was actually in progress.
@Test @MainActor func humanPromptCountsAsWork() {
    let text = [#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#,
                #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"go"}]}}"#]
        .joined(separator: "\n")
    #expect(TranscriptIndex.working(inTail: Data(text.utf8)) == true)
}

@Test @MainActor func promptWithAnImageAlsoCountsAsWork() {
    let text = [#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#,
                #"{"type":"user","message":{"content":[{"type":"image"},{"type":"text"}]}}"#]
        .joined(separator: "\n")
    #expect(TranscriptIndex.working(inTail: Data(text.utf8)) == true)
}

@Test @MainActor func wakingUpFromABackgroundTaskCountsAsWork() {
    let text = [#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#,
                #"{"type":"user","message":{"content":"<task-notification>\n<task-id>abc</task-id>"}}"#]
        .joined(separator: "\n")
    #expect(TranscriptIndex.working(inTail: Data(text.utf8)) == true)
}

/// Claude Code writes the trace of a `/clear` as a user message. That doesn't
/// count as a turn: otherwise the dozens of such stubs seen in real transcripts
/// would show up as "working" again.
@Test @MainActor func traceOfClearIsNotWork() {
    let text = [#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#,
                #"{"type":"user","message":{"content":"<local-command-caveat>Caveat: …"}}"#,
                #"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#,
                #"{"type":"user","message":{"content":"<local-command-stdout>Reconnected.</local-command-stdout>"}}"#]
        .joined(separator: "\n")
    #expect(TranscriptIndex.working(inTail: Data(text.utf8)) == false)
}

@Test @MainActor func stubMadeOnlyOfClearTracesIsNotASession() {
    let text = [#"{"type":"user","message":{"content":"<local-command-caveat>Caveat: …"}}"#,
                #"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#]
        .joined(separator: "\n")
    #expect(TranscriptIndex.working(inTail: Data(text.utf8)) == nil)
}

@Test @MainActor func noClaudeRecordsMeansNoVerdict() {
    // real case: only mode/attachment/user/last-prompt entries, no assistant record at all
    let stub = #"{"type":"last-prompt","leafUuid":"x"}"# + "\n" + #"{"type":"mode"}"#
    #expect(TranscriptIndex.working(inTail: Data(stub.utf8)) == nil)
}

@Test @MainActor func lastRecordOverridesEarlierOnes() {
    let text = [#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#,
                #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#].joined(separator: "\n")
    #expect(TranscriptIndex.working(inTail: Data(text.utf8)) == true)
}
