import Cocoa
import Combine
import AutomergeRepo

class DocumentViewController: NSViewController {

    @IBOutlet weak var countLabel: NSTextField!
    @IBOutlet weak var sharingStatus: NSTextField!
    @IBOutlet weak var sharingToggleButton: NSButton!

    var subscriptions = Set<AnyCancellable>()
    var documentStatus: SharingService.DocumentStatus? {
        didSet {
            switch documentStatus {
            case .none:
                sharingStatus?.stringValue = "not registered"
                sharingToggleButton.state = .off
            case .some(.registered):
                sharingStatus?.stringValue = "registered"
                sharingToggleButton.state = .on
            case .some(.registrationFailed(let error)):
                sharingStatus?.stringValue = "registrationFailed: \(error.localizedDescription)"
                sharingToggleButton.state = .off
            }
        }
    }
    
    var document: Document? {
        didSet {
            subscriptions = []
            sharingToggleButton.isEnabled = document != nil
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
                    await SharingService.shared
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
    
    @IBAction func toggleSharing(_ sender: Any) {
        guard let countStore = document?.countStore else {
            return
        }
        
        Task {
            if sharingToggleButton.state == .on {
                await SharingService.shared.share(store: countStore)
            } else {
                await SharingService.shared.stopSharing(id: countStore.id)
            }
        }
    }
        
}

