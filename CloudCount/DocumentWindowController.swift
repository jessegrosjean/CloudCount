import Cocoa

class DocumentWindowController: NSWindowController {

    override var document: AnyObject? {
        didSet {
            (contentViewController as! DocumentViewController).document = document as? Document
        }
    }
    
}
