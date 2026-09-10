import Testing
@testable import EmulatorKit

@Suite struct EmulatorKitSmokeTests {
    @Test func versionIsSet() {
        #expect(!EmulatorKitInfo.version.isEmpty)
    }
}
