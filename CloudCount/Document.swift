import Cocoa
import Combine
import Automerge

class Document: NSDocument {
    
    private let eventsInner = PassthroughSubject<CountStore.Event, Never>()
    private var cancelable: AnyCancellable?

    override init() {
        countStore = .init()
        super.init()
    }

    convenience init(type: String) throws {
        // called only when creating a _new_ document
        self.init()
        self.fileType = type
        defer { countStore = countStore }
    }
    
    convenience init(contentsOf url: URL, ofType typeName: String) throws {
        // called when opening a document
        self.init()
        fileURL = url
        fileType = typeName
        try read(from: url, ofType: typeName)
        defer { countStore = countStore }
    }
    
    convenience init(for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String) throws {
        // called when NSDocument reopens documents on launch
        try self.init(contentsOf: contentsURL, ofType: typeName)
        self.updateChangeCount(.changeReadOtherContents)
    }
    
    override class var autosavesInPlace: Bool {
        true
    }
    
    override var allowsDocumentSharing: Bool {
        true
    }

    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: .init("Main"), bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: .init("Document Window Controller")) as! NSWindowController
        addWindowController(windowController)
    }

    public lazy var events: AnyPublisher<CountStore.Event, Never> = {
        eventsInner.eraseToAnyPublisher()
    }()

    public var countStore: CountStore {
        didSet {
            cancelable = countStore.events
                .receive(on: RunLoop.main)
                .sink { [weak self] event in
                    self?.updateChangeCount(.changeDone)
                    self?.eventsInner.send(event)
                }
            updateChangeCount(.changeDone)
            eventsInner.send(.countChanged(countStore.count))
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        countStore.save()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let newCountStore = try CountStore(data: data)
        
        if newCountStore.id == countStore.id {
            try countStore.automerge.merge(other: newCountStore.automerge)
        } else {
            countStore = newCountStore
        }
    }
    
}
