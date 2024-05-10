import Cocoa
import Combine
import AutomergeRepo

class DocumentViewController: NSViewController {

    @IBOutlet weak var countLabel: NSTextField!
    @IBOutlet weak var cloudStatus: NSTextField!
    @IBOutlet weak var cloudToggleButton: NSButton!

    var subscriptions = Set<AnyCancellable>()
    var documentStatus: CloudService.DocumentStatus? {
        didSet {
            switch documentStatus {
            case .none:
                cloudStatus?.stringValue = "not registered"
                cloudToggleButton.state = .off
            case .some(.registered):
                cloudStatus?.stringValue = "registered"
                cloudToggleButton.state = .on
            case .some(.registrationFailed(let error)):
                cloudStatus?.stringValue = "registrationFailed: \(error.localizedDescription)"
                cloudToggleButton.state = .off
            }
        }
    }
    
    var document: Document? {
        didSet {
            subscriptions = []
            cloudToggleButton.isEnabled = document != nil
            countLabel.stringValue = "\(document?.countStore.count ?? 0)"
            documentStatus = nil

            document?.events.sink { [weak self] event in
                switch event {
                case .countChanged(let count):
                    self?.countLabel?.stringValue = "\(count)"
                }
            }.store(in: &subscriptions)

            if let id = document?.countStore.id {
                Task {
                    await CloudService.shared
                        .documentStatus(id: id)
                        .receive(on: RunLoop.main)
                        .sink { [weak self] documentStatus in
                            self?.documentStatus = documentStatus
                        }.store(in: &subscriptions)
                }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let temp = documentStatus
        documentStatus = temp // refresh
    }
    
    @IBAction func increment(_ sender: Any) {
        do {
            try document?.countStore.increment(by: 1)
        } catch {
            presentError(error)
        }
    }

    @IBAction func decrement(_ sender: Any) {
        do {
            try document?.countStore.increment(by: -1)
        } catch {
            presentError(error)
        }
    }
    
    @IBAction func toggleCloud(_ sender: Any) {
        guard let countStore = document?.countStore else {
            return
        }
        
        Task {
            if cloudToggleButton.state == .on {
                await CloudService.shared.add(store: countStore)
            } else {
                await CloudService.shared.remove(id: countStore.id)
            }
        }
    }
        
}

