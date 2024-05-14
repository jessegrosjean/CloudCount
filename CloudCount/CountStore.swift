import Automerge
import AutomergeRepo
import Foundation
import Combine

public class CountStore {

    public enum Event {
        case countChanged(Int64)
    }
    
    public let id: DocumentId
    
    private var cloud: Bool
    private var heads: Set<ChangeHash> = []
    private var automergeSubscription: AnyCancellable?
    private let eventsInner: PassthroughSubject<Event, Never> = .init()

    init(id: DocumentId = .init(), cloud: Bool = false, automerge: Automerge.Document = .init()) {
        self.id = id
        self.cloud = cloud
        self.automerge = automerge
        defer { self.automerge = automerge }
    }

    deinit {
        let id = id
        Task {
            await CloudService.shared.remove(id: id)
        }
    }

    public lazy var events: AnyPublisher<Event, Never> = {
        eventsInner.eraseToAnyPublisher()
    }()

    public var count: Int64 {
        guard let value = try? automerge.get(obj: .ROOT, key: "count") else {
            return 0
        }
        switch value {
        case .Object:
            return 0
        case .Scalar(let scalar):
            switch scalar {
            case .Counter(let count):
                return count
            default:
                return 0
            }
        }
    }
    
    public var automerge: Automerge.Document {
        didSet {
            heads = automerge.heads()
            eventsInner.send(.countChanged(count))
            automergeSubscription = automerge
                .objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    let newHeads = self.automerge.heads()
                    if newHeads != self.heads {
                        self.heads = newHeads
                        self.eventsInner.send(.countChanged(self.count))
                    }
                }
        }
    }
    
    func toggleCloud() async {
        if cloud {
            await CloudService.shared.remove(id: id)
        } else {
            await CloudService.shared.share(store: self)
        }
    }

    public func increment(by delta: Int64) throws {
        try createCountIfNeeded()
        try automerge.increment(obj: .ROOT, key: "count", by: delta)
    }
    
    private func createCountIfNeeded() throws {
        if case .Scalar(.Counter) = try automerge.get(obj: .ROOT, key: "count") {
            // Good, we have counter
        } else {
            try automerge.put(obj: .ROOT, key: "count", value: .Counter(0))
        }
    }

}

extension CountStore {
    
    convenience init(data: Data) throws {
        let propertList = try PropertyListSerialization.propertyList(from: data, format: nil)
        
        guard
            let properties = propertList as? Dictionary<String, Any>,
            let idString = properties["id"] as? String,
            let documentId = DocumentId(idString),
            let data = properties["data"] as? Data
        else {
            fatalError()
        }

        let cloud = properties["cloud"] as? Bool ?? false
        let automerge = try Automerge.Document(data)
        
        self.init(
            id: documentId,
            cloud: cloud,
            automerge: automerge
        )
    }
    
    public func save() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "id" : id.id,
            "cloud" : false,
            "data" : automerge.save()
        ], format: .binary, options: 0)
    }

}
