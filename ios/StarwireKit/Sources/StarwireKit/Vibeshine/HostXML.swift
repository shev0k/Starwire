import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A GameStream-style XML answer: `<root status_code="200" status_message="...">` with one
/// level of child elements, some of them repeated (`<App>` in the app list).
public struct HostXML: Equatable, Sendable {
    /// The `status_code` attribute. Classic routes answer HTTP 200 and put the real result here.
    public var statusCode: Int
    public var statusMessage: String?
    /// The root's direct children that hold text, by name. A repeated name keeps the last.
    public var fields: [String: String]
    /// Elements that hold other elements (`<App>`), in order, each as its children's text.
    public var records: [(name: String, fields: [String: String])]

    public static func == (lhs: HostXML, rhs: HostXML) -> Bool {
        lhs.statusCode == rhs.statusCode && lhs.statusMessage == rhs.statusMessage && lhs.fields == rhs.fields
            && lhs.records.map(\.name) == rhs.records.map(\.name) && lhs.records.map(\.fields) == rhs.records.map(\.fields)
    }

    public var isOK: Bool { statusCode == 200 }

    public subscript(name: String) -> String? { fields[name] }

    public enum ParseError: Error, Equatable {
        case notXML(String)
        case noRoot
    }

    public static func parse(_ data: Data) throws -> HostXML {
        // Some hosts announce UTF-16 while sending UTF-8, as HttpManager.fixXmlVersion notes
        var data = data
        if let text = String(data: data, encoding: .utf8), text.range(of: "UTF-16", options: .caseInsensitive) != nil {
            data = Data(text.replacingOccurrences(of: "UTF-16", with: "UTF-8", options: .caseInsensitive).utf8)
        }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw ParseError.notXML(parser.parserError.map { "\($0)" } ?? "unknown")
        }
        guard let status = reader.rootAttributes else {
            throw ParseError.noRoot
        }
        return HostXML(statusCode: Int(status["status_code"] ?? "") ?? 0, statusMessage: status["status_message"],
                       fields: reader.fields, records: reader.records)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var rootAttributes: [String: String]?
        var fields: [String: String] = [:]
        var records: [(name: String, fields: [String: String])] = []
        private var path: [String] = []
        private var text = ""
        private var record: [String: String]?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if path.isEmpty {
                rootAttributes = attributes
            } else if path.count == 1 {
                record = nil
            } else if path.count == 2, record == nil {
                record = [:]
            }
            path.append(name)
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let depth = path.count
            path.removeLast()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if depth == 3 {
                record?[name] = value
            } else if depth == 2 {
                if let record {
                    records.append((name, record))
                    self.record = nil
                } else {
                    fields[name] = value
                }
            }
            text = ""
        }
    }
}
