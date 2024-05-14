import Foundation
import Combine
import Automerge
import AutomergeRepo

@AutomergeRepo
public final class CloudService {
    
    public static let shared = CloudService()
    
    public struct Status {
        public let state: WebSocketProviderState
        public let error: Error?
    }
    
    public enum DocumentStatus {
        case registered
        case registrationFailed(Error)
    }
    
    private let repo = Repo(sharePolicy: SharePolicy.agreeable)
    private var websocket = WebSocketProvider(.init(reconnectOnError: false, loggingAt: .tracing))
    private let statusInner: CurrentValueSubject<Status, Never> = .init(.init(state: .disconnected, error: nil))
    private let documentsStatusInner: CurrentValueSubject<[DocumentId : DocumentStatus], Never> = .init([:])
    private var websocketStateCancelable: AnyCancellable?

    init() {
        repo.addNetworkAdapter(adapter: websocket)
        
        websocketStateCancelable = websocket.statePublisher.sink { [weak self] state in
            switch state {
            case .connected:
                self?.statusInner.value = .init(state: .connected, error: nil)
            case .ready:
                self?.statusInner.value = .init(state: .ready, error: nil)
            case .reconnecting:
                self?.statusInner.value = .init(state: .reconnecting, error: nil)
            case .disconnected:
                self?.statusInner.value = .init(state: .disconnected, error: nil)
            }
        }
        
        Task {
            do {
                try await websocket.connect(to: URL(string: "wss://sync.automerge.org/")!)
            } catch {
                statusInner.value = .init(state: .disconnected, error: error)
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
    
    public func share(store: CountStore) async {
        let id = store.id

        do {
            if repo.documentIds().contains(id) {
                let handle = try await repo.find(id: id)
                try handle.doc.merge(other: store.automerge)
                store.automerge = handle.doc
                documentsStatusInner.value[id] = .registered
            } else {
                let handle = try await repo.create(doc: store.automerge, id: id)
                assert(handle.doc === store.automerge)
                documentsStatusInner.value[id] = .registered
            }
        } catch {
            documentsStatusInner.value[id] = .registrationFailed(error)
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
