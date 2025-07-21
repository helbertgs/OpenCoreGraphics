import Foundation

/// An abstraction for data-reading tasks that eliminates the need to manage a raw memory buffer.
/// 
/// Data provider objects abstract the data-access task and eliminate the need for applications to manage data through a raw memory buffer.
public class CGDataProvider {

    // MARK: - Getting Data from a Data Provider
    
    /// Returns a copy of the provider’s data.
    public var data: Data?

    // MARK: - Instance Properties
    public var info: UnsafeMutablePointer<UInt8>?

    // MARK: - Creating Direct-Access Data Providers

    /// Creates a data provider that reads from a Data object.
    /// 
    /// You can use this function when you need to represent Core Graphics data as a Data type. 
    /// For example, you might create a Data object when reading data from the pasteboard.
    /// - Parameter data: The Data object to read from.
    public init(data: Data?) {
        self.data = data
    }

    /// Creates a direct-access data provider that uses a URL to supply data.
    /// 
    /// You use this function to create a direct-access data provider that supplies data from a URL. 
    /// When you supply Core Graphics with a direct-access data provider, Core Graphics obtains data from your program in a single entire block.
    /// - Parameter url: A URL object for the URL that you want to read the data from.
    public init(url: URL) {
        self.data = try? .init(contentsOf: url)
    }

    /// Creates a direct-access data provider that uses a file to supply data.
    /// 
    /// You use this function to create a direct-access data provider that supplies data from a file. 
    /// When you supply Core Graphics with a direct-access data provider, Core Graphics obtains data from your program in a single block.
    /// - Parameter filename: The full or relative pathname to use for the data provider. When you supply Core Graphics data via the provider, it reads the data from the specified file.
    public init(filename: String) {
        let url = URL(fileURLWithPath: filename)
        self.data = try? .init(contentsOf: url)
    }
}

extension CGDataProvider : Equatable {
    public static func == (lhs: CGDataProvider, rhs: CGDataProvider) -> Bool {
        return lhs.data == rhs.data
    }
}

extension CGDataProvider : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
    }
}