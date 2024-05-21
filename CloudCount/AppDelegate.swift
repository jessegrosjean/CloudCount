import Cocoa
import Network

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    override init() {
        _ = DocumentController.shared

        super.init()
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = DocumentController()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}

