import Foundation
import Combine
import Automerge
import AutomergeRepo

@AutomergeRepo
public final class CloudService {
    
    public static let shared = CloudService()
    
    public enum Status {
        case online
        case offline(Error?)
    }
    
    public enum DocumentStatus {
        case registered
        case registrationFailed(Error)
    }
    
    private let repo = Repo(sharePolicy: SharePolicy.agreeable)
    private var websocket = WebSocketProvider(.init(reconnectOnError: false, loggingAt: .tracing))
    private let statusInner: CurrentValueSubject<Status, Never> = .init(.offline(nil))
    private let documentsStatusInner: CurrentValueSubject<[DocumentId : DocumentStatus], Never> = .init([:])

    init() {
        repo.addNetworkAdapter(adapter: websocket)
        Task {
            do {
                try await websocket.connect(to: URL(string: "wss://sync.automerge.org/")!)
                statusInner.value = .online
            } catch {
                statusInner.value = .offline(error)
            }
        }
    }
    
    public lazy var status: AnyPublisher<Status, Never> = {
        statusInner.eraseToAnyPublisher()
    }()

    public lazy var documentsStatus: AnyPublisher<[DocumentId : DocumentStatus], Never> = {
        documentsStatusInner.eraseToAnyPublisher()
    }()

    public func documentStatus(id: DocumentId) -> AnyPublisher<DocumentStatus?, Never> {
        documentsStatusInner
            .map { documentsStatus in
                documentsStatus[id]
            }.eraseToAnyPublisher()
    }
    
    public func add(store: CountStore) async {
        let id = store.id

        do {
            let handle = try await repo.find(id: id)
            try handle.doc.merge(other: store.automerge)
            store.automerge = handle.doc
            documentsStatusInner.value[id] = .registered
        } catch {
            do {
                let handle = try await repo.create(doc: store.automerge, id: id)
                assert(handle.doc === store.automerge)
                documentsStatusInner.value[id] = .registered
            } catch {
                documentsStatusInner.value[id] = .registrationFailed(error)
            }
        }
    }

    public func remove(id: DocumentId) async {
        do {
            try await repo.delete(id: id)
        } catch {
            // should only throw if not registered in first place
        }
        documentsStatusInner.value.removeValue(forKey: id)
    }
    
    public func shutdown() async {
        await websocket.disconnect()
    }
    
}
