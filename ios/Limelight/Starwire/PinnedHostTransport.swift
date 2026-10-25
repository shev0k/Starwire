//
//  PinnedHostTransport.swift
//  Starwire
//
//  StarwireKit's HostTransport over HTTPS, the way HttpManager talks to a PC: the PC must show
//  exactly the certificate pinned at pairing, and this client answers with its own certificate
//  from the Keychain (StarwireIdentity). Nothing else is trusted.
//

import Foundation
import Security
import StarwireKit

final class PinnedHostTransport: NSObject, HostTransport, URLSessionDelegate, @unchecked Sendable {
    let baseURL: URL
    let pinnedCertificate: Data
    private let sessionLock = NSLock()
    private var madeSession: URLSession?

    // Made on first use. A session keeps its delegate until it is invalidated, so whoever owns
    // this transport calls close() when done with it.
    private var session: URLSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let madeSession {
            return madeSession
        }
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        madeSession = session
        return session
    }

    /// `address` is the PC's address as the app keeps it ("192.0.2.10", "[2001:db8::1]:47989"),
    /// `httpsPort` its HTTPS port and `certificate` the DER certificate pinned at pairing.
    init?(address: String, httpsPort: Int, certificate: Data) {
        let host = Self.hostPart(of: address)
        guard !host.isEmpty, let url = URL(string: "https://\(host.contains(":") ? "[\(host)]" : host):\(httpsPort)") else {
            return nil
        }
        baseURL = url
        pinnedCertificate = certificate
    }

    /// Lets requests on their way finish, then ends the session.
    func close() {
        sessionLock.lock()
        madeSession?.finishTasksAndInvalidate()
        madeSession = nil
        sessionLock.unlock()
    }

    /// "192.0.2.10:47989" -> "192.0.2.10", "[2001:db8::1]:47989" -> "2001:db8::1".
    static func hostPart(of address: String) -> String {
        if address.hasPrefix("["), let end = address.firstIndex(of: "]") {
            return String(address[address.index(after: address.startIndex)..<end])
        }
        let colons = address.filter { $0 == ":" }.count
        if colons == 1, let colon = address.firstIndex(of: ":") {
            return String(address[..<colon])
        }
        return address
    }

    func send(_ request: HostRequest) async throws -> HostResponse {
        guard let url = URL(string: request.pathAndQuery, relativeTo: baseURL) else {
            throw VibeshineError.unreadable("bad path \(request.path)")
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        if request.method == .post {
            urlRequest.httpBody = Data()
        }
        let (data, response) = try await session.data(for: urlRequest)
        return HostResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = challenge.protectionSpace.serverTrust,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count == 1,
                  SecCertificateCopyData(chain[0]) as Data == pinnedCertificate else {
                StarwireLog.error("The PC's certificate isn't the one pinned at pairing", StarwireLog.network)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        case NSURLAuthenticationMethodClientCertificate:
            guard let credential = Self.clientCredential() else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, credential)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// This client's certificate and key, from the PKCS #12 in the Keychain. Its passphrase is
    /// moonlight-ios's fixed "limelight": the Keychain item is what protects it.
    static func clientCredential() -> URLCredential? {
        guard let p12 = StarwireIdentity.data(forItem: IdentityItem.pkcs12.rawValue) else { return nil }
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, [kSecImportExportPassphrase as String: "limelight"] as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            StarwireLog.error("The client certificate couldn't be opened (OSStatus \(status))", StarwireLog.network)
            return nil
        }
        let identity = identityRef as! SecIdentity
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        return URLCredential(identity: identity, certificates: certificate.map { [$0] }, persistence: .forSession)
    }
}
