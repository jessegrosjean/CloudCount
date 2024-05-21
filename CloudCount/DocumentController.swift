import AppKit

class DocumentController: NSDocumentController {
    override init() {
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        try super.makeUntitledDocument(ofType: typeName)
    }
}
