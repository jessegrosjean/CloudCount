import Cocoa
import Combine
import AutomergeRepo

class SharingServiceViewController: NSViewController {

    @IBOutlet weak var textView: NSTextView!

    var serviceStatus: SharingService.Status = .init(state: .disconnected, error: nil)
    var documentsStatus: [DocumentId : SharingService.DocumentStatus] = [:]
    var subscriptions = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            let statusPublisher = await SharingService.shared.status
            let documentsStatusPublisher = await SharingService.shared.documentsStatus
            
            documentsStatusPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] repoStatus in
                    self?.documentsStatus = repoStatus
                    self?.update()
                }.store(in: &subscriptions)

            statusPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] websocketStatus in
                    self?.serviceStatus = websocketStatus
                    self?.update()
                }.store(in: &subscriptions)
        }
    }
    
    func update() {
        guard let storage = textView.textStorage else {
            return
        }
        
        var string = "Automerge Cloud: \(serviceStatus.state)"
        
        if let error = serviceStatus.error {
            string += " (\(error.localizedDescription))"
        }
        
        string += "\n\nRegistered Documents:\n\n"
        
        for id in documentsStatus.keys.sorted() {
            switch documentsStatus[id]! {
            case .registered:
                string += "automerge:\(id)\n"
            case .registrationFailed:
                break
            }
        }
        
        storage.replaceCharacters(in: .init(location: 0, length: storage.length), with: .init(string: string))
    }
    
}
