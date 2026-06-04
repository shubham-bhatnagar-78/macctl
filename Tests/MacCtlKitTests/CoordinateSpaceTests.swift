import Testing
import CoreGraphics
@testable import MacCtlKit

@Suite("CoordinateSpace")
struct CoordinateSpaceTests {
    @Test func retinaToLogical() {
        let physical = CGPoint(x: 400, y: 400)
        let logical = CoordinateSpace.toLogical(physical, scaleFactor: 2.0)
        #expect(logical.x == 200)
        #expect(logical.y == 200)
    }

    @Test func logicalToPhysical() {
        let logical = CGPoint(x: 200, y: 200)
        let physical = CoordinateSpace.toPhysical(logical, scaleFactor: 2.0)
        #expect(physical.x == 400)
        #expect(physical.y == 400)
    }

    @Test func nonRetinaNoChange() {
        let point = CGPoint(x: 300, y: 150)
        let logical = CoordinateSpace.toLogical(point, scaleFactor: 1.0)
        #expect(logical.x == 300)
        #expect(logical.y == 150)
    }
}
