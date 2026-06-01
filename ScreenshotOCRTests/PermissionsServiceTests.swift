import XCTest
@testable import ScreenshotOCR

@MainActor
final class PermissionsServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "test.screenshotocr.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    /// We can't force Screen Recording state in unit tests, but we can verify
    /// the `notDetermined` vs `denied` distinction driven by the persisted
    /// "didRequest" flag — the only state PermissionsService owns by itself.
    func test_refresh_whenSystemDeniesAndNeverAsked_isNotDetermined() {
        defaults.set(false, forKey: PermissionsService.didRequestScreenRecordingKey)
        let service = PermissionsService(defaults: defaults)
        service.refresh()
        // If running with permission already granted (e.g. CI host that grants
        // by default), accept that branch — otherwise enforce notDetermined.
        if !CGPreflightScreenCaptureAccess() {
            XCTAssertEqual(service.screenRecording, .notDetermined)
        }
    }

    func test_refresh_whenSystemDeniesAndPreviouslyAsked_isDenied() {
        defaults.set(true, forKey: PermissionsService.didRequestScreenRecordingKey)
        let service = PermissionsService(defaults: defaults)
        service.refresh()
        if !CGPreflightScreenCaptureAccess() {
            XCTAssertEqual(service.screenRecording, .denied)
        }
    }

    func test_requestScreenRecording_setsDidRequestFlag() {
        let service = PermissionsService(defaults: defaults)
        _ = service.requestScreenRecording()
        XCTAssertTrue(defaults.bool(forKey: PermissionsService.didRequestScreenRecordingKey))
    }
}
