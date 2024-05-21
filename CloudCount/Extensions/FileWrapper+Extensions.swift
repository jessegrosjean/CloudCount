import Foundation

extension FileWrapper {

    public convenience init(fileName: String, regularFileWithContents contents: Data) {
        self.init(regularFileWithContents: contents)
        self.preferredFilename = fileName
    }

    func removeChildren() {
        guard let children = fileWrappers?.values else {
            return
        }
        for child in children {
            removeFileWrapper(child)
        }
    }
    
    subscript(_ fileName: String) -> FileWrapper? {
        fileWrappers?[fileName]
    }
    
    func debugHiearhcy(indent: Int = 0) -> String {
        var string =  String(repeating: "  ", count: indent) + (filename ?? preferredFilename ?? "unnamed")
        if isDirectory, let fileWrappers {
            for key in fileWrappers.keys.sorted() {
                string += "/\n" + fileWrappers[key]!.debugHiearhcy(indent: indent + 1)
            }
        }
        return string
    }
    
    func copyTree() -> FileWrapper {
        .init(serializedRepresentation: serializedRepresentation!)!
    }
        
}
