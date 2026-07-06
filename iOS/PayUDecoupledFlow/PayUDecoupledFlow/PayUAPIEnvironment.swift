//
//  PayUAPIEnvironment.swift
//  PayUDecoupledFlow
//

import Foundation

enum PayUAPIEnvironment {
    case test
    case production

    var paymentURL: URL {
        URL(string: isTest ? "https://test.payu.in/_payment" : "https://secure.payu.in/_payment")!
    }

    var authDataURL: URL {
        URL(string: isTest ? "https://test.payu.in/decoupled/AuthData" : "https://secure.payu.in/decoupled/AuthData")!
    }

    var authorizeURL: URL {
        URL(string: isTest ? "https://test.payu.in/AuthorizeTransaction.php" : "https://secure.payu.in/AuthorizeTransaction.php")!
    }

    private var isTest: Bool { self == .test }
}

extension Dictionary where Key == String, Value == String {
    var formURLEncoded: Data {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._*"))
        let query = sorted { $0.key < $1.key }
            .map { pair in
                let k = pair.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? pair.key
                let v = pair.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? pair.value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(query.utf8)
    }
}
