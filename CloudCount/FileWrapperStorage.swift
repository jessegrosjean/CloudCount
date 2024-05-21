import Foundation
import Automerge
import AutomergeRepo
import Combine

public struct FileWrapperStorage {
    
    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? {
            "DocumentStorageError: \(msg)"
        }

        public init(msg: String) {
            self.msg = msg
        }
    }

    let id: DocumentId
    var doc: Automerge.Document
    var fileWrapper: FileWrapper
    var fileWrapperHeads: Set<ChangeHash>
    var unsavedChanges: [String : Data]

    public init(id: DocumentId, doc: Automerge.Document) {
        self.id = id
        self.doc = doc
        self.fileWrapperHeads = doc.heads()
        self.unsavedChanges = [:]
        self.fileWrapper = .init(directoryWithFileWrappers: [
            "id" : .init(regularFileWithContents: id.id.data(using: .utf8)!),
            "snapshots" : .init(directoryWithFileWrappers: [doc.headsKey : .init(regularFileWithContents: doc.save())]),
            "incrementals" : .init(directoryWithFileWrappers: [:])
        ])
    }
    
    public init(fileWrapper: FileWrapper) throws {
        let (id, snapshotData, _, _) = try Self.extract(fileWrapper: fileWrapper)
        self.init(id: id, doc: try .init(snapshotData))
        self.doc = try read(fileWrapper)
    }
    
    public mutating func read(_ readWrapper: FileWrapper) throws -> Automerge.Document {
        guard readWrapper !== fileWrapper else {
            return doc
        }
        
        let (_, _, snapshots, incrementals) = try Self.extract(fileWrapper: fileWrapper)
        let (readId, _, readSnapshots, readIncrementals) = try Self.extract(fileWrapper: readWrapper)

        guard id == readId else {
            throw Error(msg: "Read ID doesn't match")
        }

        if doc.heads() != fileWrapperHeads {
            unsavedChanges[doc.headsKey] = try doc.encodeChangesSince(heads: fileWrapperHeads)
        }
        
        var newChanges: [String : Data] = [:]
                    
        for readKey in Set(readSnapshots.fileWrappers!.keys).subtracting(snapshots.fileWrappers!.keys) {
            if let data = readSnapshots[readKey]?.regularFileContents {
                newChanges[readKey] = data
            }
        }

        for readKey in Set(readIncrementals.fileWrappers!.keys).subtracting(incrementals.fileWrappers!.keys) {
            if let data = readIncrementals[readKey]?.regularFileContents {
                newChanges[readKey] = data
            }
        }
                
        for (key, data) in newChanges {
            do {
                try doc.applyEncodedChanges(encoded: data)
            } catch {
                print("Failed apply changes: \(key)")
            }
        }
        
        self.fileWrapper = readWrapper
        self.fileWrapperHeads = doc.heads()
        
        return doc
    }
    
    public mutating func save() throws -> FileWrapper {
        let heads = doc.heads()
        
        if heads != fileWrapperHeads {
            unsavedChanges[doc.headsKey] = try doc.encodeChangesSince(heads: fileWrapperHeads)
        }

        guard !unsavedChanges.isEmpty else {
            return fileWrapper
        }
        
        for each in unsavedChanges {
            fileWrapper["incrementals"]!.addFileWrapper(.init(
                fileName: each.key,
                regularFileWithContents: each.value
            ))
        }
        
        fileWrapperHeads = heads
        unsavedChanges = [:]
        
        if fileWrapper["incrementals"]!.fileWrappers!.count > 3 {
            try compact()
        }
        
        return fileWrapper
    }
    
    public mutating func compact() throws {
        _ = try save()
        
        fileWrapper["incrementals"]!.removeChildren()
        fileWrapper["snapshots"]!.removeChildren()
        fileWrapper["snapshots"]!.addFileWrapper(.init(
            fileName: doc.headsKey,
            regularFileWithContents: doc.save()
        ))
    }
    
    private static func extract(fileWrapper: FileWrapper) throws -> (
        id: DocumentId,
        data: Data,
        snapshots: FileWrapper,
        incrementals: FileWrapper
    ) {
        guard
            let idData = fileWrapper["id"]?.regularFileContents,
            let id = String(data: idData, encoding: .utf8).map({ DocumentId($0) }) ?? nil
        else {
            throw Error(msg: "Invalid FileWrapper: Missing or Bad ID")
        }

        guard let snapshots = fileWrapper["snapshots"], snapshots.isDirectory else {
            throw Error(msg: "Invalid FileWrapper: Missing snapshots folder")
        }
        
        guard let data = snapshots.fileWrappers?.first?.value.regularFileContents else {
            throw Error(msg: "Invalid FileWrapper: Missing snapshot data")
        }
        
        guard let incrementals = fileWrapper["incrementals"], incrementals.isDirectory else {
            throw Error(msg: "Invalid FileWrapper: Missing incrementals folder")
        }

        return (id, data, snapshots, incrementals)
    }
    
}

extension Automerge.Document {
    var headsKey: String {
        heads().debugDescription.data(using: .utf8)!.sha256()
    }
}

