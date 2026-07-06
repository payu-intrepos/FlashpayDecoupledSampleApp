//
//  PayUHashGenerator.swift
//  PayUDecoupledFlow
//

import CryptoKit
import Foundation

struct PayUHashResult {
    let hashString: String
    let hashValue: String
}

struct PayUHashGenerator {

    private static let hashFieldKeys = [
        "key", "txnid", "amount", "productinfo", "firstname", "email",
        "udf1", "udf2", "udf3", "udf4", "udf5"
    ]

    /// sha512(key|txnid|amount|productinfo|firstname|email|udf1|udf2|udf3|udf4|udf5||||||SALT)
    /// Uses the same raw POST values (not URL-encoded).
    static func paymentHash(from fields: [String: String], salt: String) -> PayUHashResult {
        let parts = hashFieldKeys.map { fields[$0] ?? "" }
        let hashString = parts.joined(separator: "|") + "||||||" + salt
        let hashValue = sha512(hashString)
        return PayUHashResult(hashString: hashString, hashValue: hashValue)
    }

    /// sha512(key|referenceId|salt|date)
    static func authDataHash(
        merchantKey: String,
        referenceId: String,
        salt: String,
        date: String
    ) -> PayUHashResult {
        let hashString = [merchantKey, referenceId, salt, date].joined(separator: "|")
        let hashValue = sha512(hashString)
        return PayUHashResult(hashString: hashString, hashValue: hashValue)
    }

    /// sha512(key|txnid|amount|authentication_info|salt)
    static func authorizeHash(
        merchantKey: String,
        txnid: String,
        amount: String,
        authenticationInfo: String,
        salt: String
    ) -> PayUHashResult {
        let hashString = [merchantKey, txnid, amount, authenticationInfo, salt].joined(separator: "|")
        let hashValue = sha512(hashString)
        return PayUHashResult(hashString: hashString, hashValue: hashValue)
    }

    static func sha512(_ input: String) -> String {
        let digest = SHA512.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
