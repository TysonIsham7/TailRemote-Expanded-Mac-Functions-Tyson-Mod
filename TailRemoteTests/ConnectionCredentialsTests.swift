import XCTest
@testable import TailRemote

@MainActor
final class ConnectionCredentialsTests: XCTestCase {
    private let key = RemoteCredentialKey(hostname: "mac.test.invalid", port: 5900, username: "test-user")

    func testReopeningFormRestoresSavedPassword() async {
        let store = TestPasswordStore()
        store.passwords[key] = "synthetic-password"
        let form = ConnectionCredentials(store: store)
        form.load(for: key, rememberPassword: true)
        XCTAssertEqual(form.password, "synthetic-password")
        let reopened = ConnectionCredentials(store: store)
        reopened.load(for: key, rememberPassword: true)
        XCTAssertEqual(reopened.password, "synthetic-password")
    }

    func testChangingMacOrDisablingRememberCannotReusePreviousPassword() async {
        let store = TestPasswordStore()
        store.passwords[key] = "synthetic-password"
        let form = ConnectionCredentials(store: store)
        form.load(for: key, rememberPassword: true)
        let other = RemoteCredentialKey(hostname: "other.test.invalid", port: 5900, username: key.username)
        form.load(for: other, rememberPassword: true)
        XCTAssertTrue(form.password.isEmpty)
        form.load(for: key, rememberPassword: true)
        form.load(for: key, rememberPassword: false)
        XCTAssertTrue(form.password.isEmpty)
    }

    func testReadFailureClearsPreviousPasswordAndExplainsError() async {
        let store = TestPasswordStore()
        store.passwords[key] = "synthetic-password"
        let form = ConnectionCredentials(store: store)
        form.load(for: key, rememberPassword: true)
        store.shouldFail = true
        form.load(for: key, rememberPassword: true)
        XCTAssertTrue(form.password.isEmpty)
        XCTAssertNotNil(form.errorMessage)
    }

    func testForgettingRemovesSavedCopyButKeepsCurrentEntryUsable() async {
        let store = TestPasswordStore()
        store.passwords[key] = "synthetic-password"
        let form = ConnectionCredentials(store: store)
        form.load(for: key, rememberPassword: true)
        XCTAssertTrue(form.forget(for: key))
        XCTAssertNil(store.passwords[key])
        XCTAssertEqual(form.password, "synthetic-password")
        form.load(for: key, rememberPassword: true)
        XCTAssertTrue(form.password.isEmpty)
    }

    func testCancelledUnlockKeepsTheTypedPassword() async {
        let store = TestPasswordStore()
        store.passwords[key] = "synthetic-password"
        store.shouldFail = true
        store.failureStatus = errSecUserCanceled
        let form = ConnectionCredentials(store: store)
        form.password = "typed-while-locked"
        form.load(for: key, rememberPassword: true)
        XCTAssertEqual(form.password, "typed-while-locked")
        XCTAssertEqual(form.errorMessage, "Couldn’t unlock the saved password. You can enter it again.")
        XCTAssertFalse(form.errorMessage?.contains("Couldn’t load") ?? false)
    }

    func testMissingItemLeavesTheFormBlankWithoutAnError() async {
        let form = ConnectionCredentials(store: TestPasswordStore())
        form.load(for: key, rememberPassword: true)
        XCTAssertTrue(form.password.isEmpty)
        XCTAssertNil(form.errorMessage)
    }

    func testLogoutClearsTheStaleLoadErrorWithoutWipingATypedPassword() async {
        let store = TestPasswordStore()
        store.shouldFail = true
        let form = ConnectionCredentials(store: store)
        form.load(for: key, rememberPassword: true)
        XCTAssertEqual(form.errorMessage, "Couldn’t load the saved password. You can enter it again.")
        form.password = "typed-after-failure"
        form.clearPresentedError()
        XCTAssertNil(form.errorMessage)
        XCTAssertEqual(form.password, "typed-after-failure")
    }

    func testFailedRemovalDoesNotClaimPasswordWasForgotten() async {
        let store = TestPasswordStore()
        store.passwords[key] = "synthetic-password"
        let form = ConnectionCredentials(store: store)
        store.shouldFail = true
        XCTAssertFalse(form.forget(for: key))
        XCTAssertNotNil(store.passwords[key])
        XCTAssertNotNil(form.errorMessage)
    }
}
