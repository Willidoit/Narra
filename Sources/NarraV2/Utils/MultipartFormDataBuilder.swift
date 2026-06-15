import Foundation

/// Minimal RFC 2388 multipart/form-data builder for POST bodies.
///
/// Used to construct the audio upload that the Grok transcription
/// endpoint expects. Keeps a small, well-defined surface so tests can
/// inspect the produced body.
public enum MultipartFormDataBuilder {

    public enum Field {
        case text(name: String, value: String)
        case file(name: String, filename: String, contentType: String, data: Data)
    }

    public struct Result {
        public let data: Data
        public let contentType: String
    }

    public static func build(boundary: String, fields: [Field]) throws -> Result {
        var body = Data()
        let crlf = "\r\n"
        for field in fields {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            switch field {
            case .text(let name, let value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
                body.append("\(value)\(crlf)".data(using: .utf8)!)
            case .file(let name, let filename, let contentType, let data):
                body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
                body.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
                body.append(data)
                body.append(crlf.data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return Result(
            data: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }
}
