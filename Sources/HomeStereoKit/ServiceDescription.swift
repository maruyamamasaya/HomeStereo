import Foundation

public struct UPnPServiceDescription: Equatable, Sendable {
    public let actions: [String]

    public init(actions: [String]) {
        self.actions = actions
    }
}

public enum ServiceDescriptionParser {
    public static func parse(data: Data) throws -> UPnPServiceDescription {
        let delegate = ServiceDescriptionParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw HomeStereoError.invalidServiceDescription }
        return UPnPServiceDescription(actions: delegate.actions)
    }
}

public enum ServiceDescriptionLoader {
    public static func load(from url: URL, session: URLSession = .shared) async throws -> UPnPServiceDescription {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HomeStereoError.invalidServiceDescription
        }
        return try ServiceDescriptionParser.parse(data: data)
    }
}

private final class ServiceDescriptionParserDelegate: NSObject, XMLParserDelegate {
    var actions: [String] = []
    private var path: [String] = []
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        path.append(elementName)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "name",
           path.count >= 3,
           path[path.count - 2] == "action",
           path[path.count - 3] == "actionList",
           !value.isEmpty {
            actions.append(value)
        }
        _ = path.popLast()
        text = ""
    }
}
