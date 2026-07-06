//
//  PayUAuthenticationAPIService.swift
//  PayUDecoupledFlow
//

import Foundation

final class PayUAuthenticationAPIService {

    static let shared = PayUAuthenticationAPIService()

    var environment: PayUAPIEnvironment = .test

    func authenticateAndAuthorize(
        key: String,
        salt: String,
        hash: String,
        date: String,
        referenceId: String,
        txnid: String,
        amount: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        fetchAuthData(key: key, hash: hash, date: date, referenceId: referenceId) { [weak self] result in
            switch result {
            case .success(let authData):
                self?.authorizeTransaction(
                    merchantKey: key,
                    salt: salt,
                    referenceId: referenceId,
                    txnid: txnid,
                    amount: amount,
                    authData: authData,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - AuthData

    func fetchAuthData(
        key: String,
        hash: String,
        date: String,
        referenceId: String,
        completion: @escaping (Result<PayUAuthDataResponse, Error>) -> Void
    ) {
        var components = URLComponents(url: environment.authDataURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "referenceId", value: referenceId)]
        guard let url = components.url else {
            return completion(.failure(PayUPaymentError.encodingFailed))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "key")
        request.setValue(hash, forHTTPHeaderField: "hash")
        request.setValue(date, forHTTPHeaderField: "Date")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                return completion(.failure(error))
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            guard (200 ... 299).contains(status), let data else {
                return completion(.failure(PayUPaymentError.httpError(status: status, body: text)))
            }

            do {
                let authData = try JSONDecoder().decode(PayUAuthDataResponse.self, from: data)
                guard authData.isSuccess else {
                    return completion(.failure(PayUPaymentError.httpError(status: status, body: text)))
                }
                completion(.success(authData))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Authorize

    func authorizeTransaction(
        merchantKey: String,
        salt: String,
        referenceId: String,
        txnid: String,
        amount: String,
        authData: PayUAuthDataResponse,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let authInfo: String
        do {
            authInfo = try PayUAuthenticationInfo(referenceId: referenceId, authData: authData).jsonString()
        } catch {
            return completion(.failure(error))
        }

        let hashResult = PayUHashGenerator.authorizeHash(
            merchantKey: merchantKey,
            txnid: txnid,
            amount: amount,
            authenticationInfo: authInfo,
            salt: salt
        )

        let form: [String: String] = [
            "key": merchantKey,
            "txnid": txnid,
            "amount": amount,
            "authentication_info": authInfo,
            "hash": hashResult.hashValue
        ]

        let body = form.formURLEncoded
        var request = URLRequest(url: environment.authorizeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { return completion(.failure(error)) }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            guard (200 ... 299).contains(status) else {
                return completion(.failure(PayUPaymentError.httpError(status: status, body: text)))
            }

            completion(.success(text))
        }.resume()
    }
}

// MARK: - GMT date header

enum PayUGMTDateFormatter {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

