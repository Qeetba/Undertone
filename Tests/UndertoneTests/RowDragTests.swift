import XCTest
@testable import UndertoneCore

/// The arithmetic of dragging one queue row among its neighbours.
final class RowDragTests: XCTestCase {

    private func drag(from source: Int, by rows: Double, count: Int = 5) -> RowDrag {
        var drag = RowDrag(source: source, count: count, rowHeight: 30)
        drag.translation = rows * 30
        return drag
    }

    // MARK: - Where the row would land

    func testASmallNudgeLeavesTheRowWhereItWas() {
        XCTAssertEqual(drag(from: 2, by: 0.4).destination, 2)
        XCTAssertEqual(drag(from: 2, by: -0.4).destination, 2)
    }

    func testDraggingPastHalfARowMovesOneSlot() {
        XCTAssertEqual(drag(from: 2, by: 0.6).destination, 3)
        XCTAssertEqual(drag(from: 2, by: -0.6).destination, 1)
    }

    func testDraggingSeveralRowsMovesSeveralSlots() {
        XCTAssertEqual(drag(from: 0, by: 3.1).destination, 3)
        XCTAssertEqual(drag(from: 4, by: -2.2).destination, 2)
    }

    func testTheRowCannotLeaveTheList() {
        XCTAssertEqual(drag(from: 1, by: 40).destination, 4)
        XCTAssertEqual(drag(from: 3, by: -40).destination, 0)
    }

    // MARK: - How the rows are drawn mid-drag

    func testTheDraggedRowFollowsThePointer() {
        XCTAssertEqual(drag(from: 1, by: 1.3).offset(forRowAt: 1), 39, accuracy: 0.001)
    }

    func testTheDraggedRowStopsAtTheEndsOfTheList() {
        XCTAssertEqual(drag(from: 1, by: 40).offset(forRowAt: 1), 90, "three rows down is the last slot")
        XCTAssertEqual(drag(from: 1, by: -40).offset(forRowAt: 1), -30)
    }

    func testRowsBetweenMakeRoomWhenDraggingDown() {
        let drag = drag(from: 1, by: 2)          // row 1 heading for slot 3
        XCTAssertEqual(drag.offset(forRowAt: 0), 0)
        XCTAssertEqual(drag.offset(forRowAt: 2), -30)
        XCTAssertEqual(drag.offset(forRowAt: 3), -30)
        XCTAssertEqual(drag.offset(forRowAt: 4), 0)
    }

    func testRowsBetweenMakeRoomWhenDraggingUp() {
        let drag = drag(from: 3, by: -2)         // row 3 heading for slot 1
        XCTAssertEqual(drag.offset(forRowAt: 0), 0)
        XCTAssertEqual(drag.offset(forRowAt: 1), 30)
        XCTAssertEqual(drag.offset(forRowAt: 2), 30)
        XCTAssertEqual(drag.offset(forRowAt: 4), 0)
    }

    // MARK: - Dropping

    func testDroppingWhereItStartedIsNotAMove() {
        XCTAssertNil(drag(from: 2, by: 0.3).move)
    }

    func testDroppingLowerPutsTheTrackInThatSlot() {
        var queue = Playlist()
        let urls = ["a", "b", "c", "d"].map { URL(fileURLWithPath: "/tmp/fake/\($0).mp3") }
        queue.append(urls)
        let move = try! XCTUnwrap(drag(from: 0, by: 2, count: 4).move)
        queue.move(fromOffsets: move.source, toOffset: move.destination)
        XCTAssertEqual(queue.items.map { $0.deletingPathExtension().lastPathComponent }, ["b", "c", "a", "d"])
    }

    func testDroppingHigherPutsTheTrackInThatSlot() {
        var queue = Playlist()
        let urls = ["a", "b", "c", "d"].map { URL(fileURLWithPath: "/tmp/fake/\($0).mp3") }
        queue.append(urls)
        let move = try! XCTUnwrap(drag(from: 3, by: -2, count: 4).move)
        queue.move(fromOffsets: move.source, toOffset: move.destination)
        XCTAssertEqual(queue.items.map { $0.deletingPathExtension().lastPathComponent }, ["a", "d", "b", "c"])
    }
}
