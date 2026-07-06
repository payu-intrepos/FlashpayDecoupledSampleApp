//
//  PayUPaymentAPIService.swift
//  PayUDecoupledFlow
//

import Foundation

// MARK: - Errors

enum PayUPaymentError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode request."
        case .decodingFailed: return "Failed to decode payment response."
        case .httpError(let status, let body): return "HTTP \(status): \(body)"
        }
    }
}

// MARK: - Card details

struct PayUCardPaymentDetails {
    let cardNumber: String
    let cardHolderName: String
    let cvv: String
    let expiryMonth: String
    let expiryYear: String
}

// MARK: - Request

struct PayUPaymentRequest {
    let parq: PayU3DS2PArqResponseModel
    let txnid: String
    let amount: String
    private let fields: [String: String]

    static func decoupled(
        merchantKey: String,
        salt: String,
        parq: PayU3DS2PArqResponseModel,
        card: PayUCardPaymentDetails,
        txnid: String
    ) -> PayUPaymentRequest {
        let amount = "1"
        var fields: [String: String] = [
            "key": merchantKey,
            "txnid": txnid,
            "amount": amount,
            "productinfo": "Nokia",
            "firstname": "No Name",
            "email": "amit.salaria@payu.in",
            "phone": "8700908382",
            "surl": "https://cbjs.payu.in/sdk/success",
            "furl": "https://cbjs.payu.in/sdk/failure",
            "pg": "CC",
            "bankcode": "CC",
            "ccnum": card.cardNumber,
            "ccname": card.cardHolderName,
            "ccvv": card.cvv,
            "ccexpmon": card.expiryMonth,
            "ccexpyr": card.expiryYear,
            "auth_only": "2",
            "threeds_authN_flow":"2",
            "txn_s2s_flow": "4",
            "termUrl": "https://acssimuat.payubiz.in/termUrl/DecoupledResponse",
            "user_credentials": "amit:salaria",
            "udf1": "udf1",
            "udf2": "udf2",
            "udf3": "udf3",
            "udf4": "udf4",
            "udf5": "udf5"
        ]

        // Hash must use the exact same raw values as POST fields (plain text, not URL-encoded).
        let hashResult = PayUHashGenerator.paymentHash(from: fields, salt: salt)
        fields["hash"] = hashResult.hashValue

        return PayUPaymentRequest(parq: parq, txnid: txnid, amount: amount, fields: fields)
    }

    func formParameters() throws -> [String: String] {
        var form = fields
        form["threeDS2RequestData"] = try parq.threeDS2RequestDataJSON()
        return form
    }


    func body() throws -> Data {
        try formParameters().formURLEncoded
    }
}

// MARK: - Service

final class PayUPaymentAPIService {

    static let shared = PayUPaymentAPIService()
    var environment: PayUAPIEnvironment = .test

    func initiatePayment(
        _ request: PayUPaymentRequest,
        completion: @escaping (Result<PayUPaymentAPIResponse, Error>) -> Void
    ) {
        let form: [String: String]
        let body: Data
        do {
            form = try request.formParameters()
            body = form.formURLEncoded
        } catch {
            return completion(.failure(error))
        }

        var urlRequest = URLRequest(url: environment.paymentURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error { return completion(.failure(error)) }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            guard (200 ... 299).contains(status) else {
                return completion(.failure(PayUPaymentError.httpError(status: status, body: text)))
            }

            do {
                let response = try PayUPaymentAPIResponse.decode(from: text)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
