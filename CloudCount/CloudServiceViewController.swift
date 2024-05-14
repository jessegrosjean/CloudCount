import Cocoa
import Combine
import AutomergeRepo

class CloudServiceViewController: NSViewController {

    @IBOutlet weak var textView: NSTextView!

    var serviceStatus: CloudService.Status = .init(state: .disconnected, error: nil)
    var documentsStatus: [DocumentId : CloudService.DocumentStatus] = [:]
    var subscriptions = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            let statusPublisher = await CloudService.shared.status
            let documentsStatusPublisher = await CloudService.shared.documentsStatus
            
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
        
        var string = "Cloud: \(serviceStatus.state)"
        
        if let error = serviceStatus.error {
            string += " (\(error.localizedDescription))"
        }
        
        string += "\n\nCloud Documents:\n\n"
        
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
