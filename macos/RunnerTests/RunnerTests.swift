import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testBundleNamesMatchTheApplicationName() {
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Hobs")
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "Hobs")
  }

  @MainActor
  func testMainWindowUsesTheApplicationName() throws {
    let appDelegate = try XCTUnwrap(NSApp.delegate as? FlutterAppDelegate)
    let window = try XCTUnwrap(appDelegate.mainFlutterWindow)
    XCTAssertEqual(window.title, "Hobs")
  }

}
