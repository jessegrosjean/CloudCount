import Cocoa
import Combine
import CloudKit
import Automerge

class Document: NSDocument {

    private let eventsInner = PassthroughSubject<CountStore.Event, Never>()
    private let statusInner = CurrentValueSubject<String, Never>("")
    private var cancelable: AnyCancellable?

    override init() {
        countStore = .init()
        storage = .init(id: countStore.id, doc: countStore.automerge)
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
        storage = try .init(fileWrapper: .init(url: url))
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

    public lazy var status: AnyPublisher<String, Never> = {
        statusInner.eraseToAnyPublisher()
    }()

    public var countStore: CountStore {
        didSet {
            if storage.doc !== countStore.automerge {
                storage = .init(id: countStore.id, doc: countStore.automerge)
            }
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
    
    var storage: FileWrapperStorage
    
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let wrapper = try storage.save()
        updateStatus()
        return wrapper
    }

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        countStore.automerge = try storage.read(fileWrapper)
        if countStore.id != storage.id {
            countStore = .init(id: storage.id, sharing: false, automerge: storage.doc)
        }
        updateStatus()
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        resolveConflictsIfNeeded()
        try super.read(from: url, ofType: typeName)
    }
    
    private func resolveConflictsIfNeeded() {
        guard
            let fileURL,
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL), !conflicts.isEmpty
        else {
            return
        }
        
        let fm = FileManager.default
        let snapshots = fileURL.appendingPathComponent("snapshots")
        let incrementals = fileURL.appendingPathComponent("incrementals")

        func merge(source: URL, destination: URL) throws {
            for s in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let d = destination.appending(component: s.lastPathComponent)
                if !fm.fileExists(atPath: d.path) {
                    try fm.copyItem(atPath: s.path, toPath: d.path)
                }
            }
        }
        
        for conflict in conflicts {
            if conflict.hasLocalContents {
                let conflictUrl = conflict.url
                let conflictSnapshots = conflictUrl.appendingPathComponent("snapshots")
                let conflictIncrementals = conflictUrl.appendingPathComponent("incrementals")
                
                do {
                    try merge(source: conflictSnapshots, destination: snapshots)
                    try merge(source: conflictIncrementals, destination: incrementals)
                    conflict.isResolved = true
                } catch {
                    Swift.print(error)
                }
            }
        }
    }
    
    private func updateStatus() {
        guard 
            let fileURL = fileURL,
            let currentVersion = NSFileVersion.currentVersionOfItem(at: fileURL)
        else {
            return
        }

        var status = "ID: \(countStore.id)\n\n"

        assert(countStore.id == storage.id)
        
        status += "File Wrapper:\n\n"

        let wrapper = storage.fileWrapper
        if let incrementals = wrapper["incrementals"] {
            status += incrementals.debugHiearhcy() + "\n"
        }
        if let snapshots = wrapper["snapshots"] {
            status += snapshots.debugHiearhcy() + "\n"
        }

        if !storage.unsavedChanges.isEmpty {
            status += "unsaved changes:\n"
            for each in storage.unsavedChanges {
                status += "  \(each.key)\n"
            }
        }
        
        status += "\nFile Versions:\n\n"
        
        let otherVersions = NSFileVersion.otherVersionsOfItem(at: fileURL) ?? []
        let allVersions = [currentVersion] + otherVersions
        
        for v in allVersions {
            status += "url: \(v.url.lastPathComponent)"

            if let localizedName = v.localizedName {
                status += ", name: \(localizedName)"
            }
            
            if let localizedNameOfSavingComputer = v.localizedNameOfSavingComputer {
                status += ", savingComputer: \(localizedNameOfSavingComputer)"
            }
            
            if v.hasLocalContents {
                status += ", local: true"
            }
            if v.isConflict {
                status += ", isConflict: true"
            }
            if v.isResolved {
                status += ", isResolved: true"
            }
            if v.isDiscardable {
                status += ", isDiscardable: true"
            }
            status += "\n"
        }
        
        statusInner.value = status
     }
    
    override func presentedItemDidGain(_ version: NSFileVersion) {
        super.presentedItemDidGain(version)
        updateStatus()
    }
    
    override func presentedItemDidLose(_ version: NSFileVersion) {
        super.presentedItemDidLose(version)
        updateStatus()
    }
    
    override func presentedItemDidResolveConflict(_ version: NSFileVersion) {
        super.presentedItemDidResolveConflict(version)
        updateStatus()
    }
        
}
