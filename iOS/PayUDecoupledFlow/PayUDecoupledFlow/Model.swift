//
//  Model.swift
//  PayUDecoupledFlow
//
//  Created by rishabh.jaiswal on 21/05/26.
//

import Foundation
import PayU3DS2Kit

// MARK: - PArq (device details)

/// Maps from `PayU3DS2Kit.PayU3DS2PArqResponse` returned by `extractDeviceDetails`.
struct PayU3DS2PArqResponseModel {

    let sdkAppID: String
    let sdkEncData: String
    let crv: String
    let kty: String
    let x: String
    let y: String
    let sdkTransID: String
    let sdkReferenceNumber: String

    init(sdkResponse: PayU3DS2Kit.PayU3DS2PArqResponse) {
        sdkAppID = sdkResponse.sdkAppID
        sdkEncData = sdkResponse.sdkEncData
        crv = sdkResponse.crv
        kty = sdkResponse.kty
        x = sdkResponse.x
        y = sdkResponse.y
        sdkTransID = sdkResponse.sdkTransID
        sdkReferenceNumber = sdkResponse.sdkReferenceNumber
    }

    func threeDS2RequestDataJSON(
        threeDSVersion: String = "2.2.0",
        sdkMaxTimeout: String = "05"
    ) throws -> String {
        let sdkEphemPubKey = PayU3DS2SDKEphemPubKey(crv: crv, kty: kty, x: x, y: y)
        let deviceRenderOptions = PayU3DS2DeviceRenderOptions(
            sdkInterface: "03",
            sdkUIType: ["05", "01", "02", "03", "04"]
        )
        let sdkInfo = PayU3DS2SDKInfo(
            sdkEncData: sdkEncData,
            sdkAppID: sdkAppID,
            sdkReferenceNumber: sdkReferenceNumber,
            sdkTransID: sdkTransID,
            sdkMaxTimeout: sdkMaxTimeout,
            deviceRenderOptions: deviceRenderOptions,
            sdkEphemPubKey: sdkEphemPubKey
        )
        let params = PayU3DS2Params(
            sdkInfo: sdkInfo,
            deviceChannel: "APP",
            threeDSVersion: threeDSVersion
        )

        guard let json = String(data: try JSONEncoder().encode(params), encoding: .utf8) else {
            throw PayUPaymentError.encodingFailed
        }
        return json
    }
}

// MARK: - Payment API response

struct PayUPaymentAPIResponse: Decodable {
    let metaData: PayUPaymentMetaData?
    let result: PayUPaymentResultData?
    let binData: PayUBinData?
    let status: String?
    let error: String?
    let message: String?

    var isSuccess: Bool {
        metaData != nil && (result?.postToBank != nil || !(result?.rawBankData?.isEmpty ?? true))
    }

    func makeChallengeParameter() -> PayU3DS2ChallengeParameter? {
        let rawFields = result?.rawBankFields ?? [:]
        let cardBin = String(binData?.cardBin ?? 0)
        if let param = result?.postToBank?.makeChallengeParameter(cardBin: cardBin, rawBankFields: rawFields) {
            return param
        }
        return PayUPostToBank.from(rawBankFields: rawFields)?.makeChallengeParameter(cardBin: cardBin, rawBankFields: rawFields)
    }

    static func decode(from json: String) throws -> PayUPaymentAPIResponse {
        guard let data = json.data(using: .utf8) else {
            throw PayUPaymentError.decodingFailed
        }
        return try JSONDecoder().decode(PayUPaymentAPIResponse.self, from: data)
    }
}

struct PayUPaymentMetaData: Codable {
    let message: String?
    let referenceId: String?
    let statusCode: String?
    let txnId: String?
    let txnStatus: String?
    let unmappedStatus: String?
    let flowType: String?
}

struct PayUPaymentResultData: Decodable {
    let postToBank: PayUPostToBank?
    let rawBankData: String?

    var rawBankFields: [String: String] {
        PayUQueryStringParser.fields(from: rawBankData)
    }

    enum CodingKeys: String, CodingKey {
        case postToBank, rawBankData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postToBank = try? c.decode(PayUPostToBank.self, forKey: .postToBank)
        rawBankData = try c.decodeIfPresent(String.self, forKey: .rawBankData)
    }
}

struct PayUPostToBank: Codable {
    let referenceId: String?
    let eci: String?
    let threeDSServerTransID: String?
    let threeDSTransID: String?
    let threeDSTransStatus: String?
    let threeDSVersion: String?
    let threeDSTransStatusReason: String?
    let cavv: String?
    let acsSignedContent: String?
    let acsReferenceNumber: String?
    let acsTransID: String?
    let acsRenderingType: PayUAcsRenderingType?
    let mfaParams: PayUMFAParams?
    let additionalInfo: PayUAdditionalInfo?
}

struct PayUAcsRenderingType: Codable {
    let acsInterface: String?
    let acsUiTemplate: String?
}

struct PayUMFAParams: Codable {
    // Matches the actual _payment API response mfaParams object exactly.
    let name: String?                   // "PAYUMFA"
    let id: String?                     // "MFAV01" → SDK mfaId
    let criticalityIndicator: Bool?     // false
    let tdyClientId: String?            // "TDY_FLIP_MER_001"
    let clientId: String?               // fallback for tdyClientId
    let tdyCardId: String?              // "ca311738-..."
    let issuerImage: String?            // bank logo URL
    let psImage: String?                // network logo URL
    let status: String?                 // "success"
    let messageType: String?            // "02"
    let data: String?                   // encrypted data string — passed as-is to SDK

    func toSDKMFAParam(cardBin: String?) -> PayU3DS2MFAParam {
        let resolvedClientId = nonEmpty(tdyClientId) ?? nonEmpty(clientId)
        return PayU3DS2MFAParam(
            tdyCardId: nonEmpty(tdyCardId),
            tdyClientId: resolvedClientId,
            issuerImage: nonEmpty(issuerImage),
            psImage: nonEmpty(psImage),
            messageType: messageType,
            name: name,
            mfaId: id,
            criticalityIndicator: criticalityIndicator ?? false,
            status: status,
            data: data,
            cardBin: cardBin
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

struct PayUAdditionalInfo: Codable {
    let authUdf1: String?
    let authUdf2: String?
    let authUdf3: String?
    let authUdf4: String?
    let authUdf5: String?
    let authUdf6: String?
    let authUdf7: String?
    let authUdf8: String?
    let authUdf9: String?
    let authUdf10: String?
}

struct PayUBinData: Codable {
    let pureS2SSupported: Bool?
    let issuingBank: String?
    let category: String?
    let cardType: String?
    let isDomestic: Bool?
    let nativeType: Int?
    let cardBin: Int?
}

// MARK: - AuthData / Authorize

struct PayUAuthDataResponse: Decodable {
    let enquiryStatus: String?
    let payuid: String?
    let cavv: String?
    let eci: String?
    let threeDSTransStatus: String?
    let threeDSTransStatusReason: String?
    let flowType: String?
    let threeDSTransID: String?
    let threeDSServerTransID: String?
    let threeDSVersion: String?
    let authFlowType: String?
    let status: String?

    var isSuccess: Bool {
        status?.uppercased() == "SUCCESS" || enquiryStatus?.lowercased() == "success"
    }

    enum CodingKeys: String, CodingKey {
        case enquiryStatus, payuid, cavv, eci, threeDSTransStatus, threeDSTransStatusReason
        case flowType, threeDSTransID, threeDSServerTransID, threeDSVersion, authFlowType, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enquiryStatus = try c.decodeIfPresent(String.self, forKey: .enquiryStatus)
        payuid = Self.decodeFlexibleString(from: c, forKey: .payuid)
        cavv = try c.decodeIfPresent(String.self, forKey: .cavv)
        eci = try c.decodeIfPresent(String.self, forKey: .eci)
        threeDSTransStatus = try c.decodeIfPresent(String.self, forKey: .threeDSTransStatus)
        threeDSTransStatusReason = try c.decodeIfPresent(String.self, forKey: .threeDSTransStatusReason)
        flowType = try c.decodeIfPresent(String.self, forKey: .flowType)
        threeDSTransID = try c.decodeIfPresent(String.self, forKey: .threeDSTransID)
        threeDSServerTransID = try c.decodeIfPresent(String.self, forKey: .threeDSServerTransID)
        threeDSVersion = try c.decodeIfPresent(String.self, forKey: .threeDSVersion)
        authFlowType = try c.decodeIfPresent(String.self, forKey: .authFlowType)
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(UInt64.self, forKey: key) { return String(value) }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decode(Double.self, forKey: key) {
            return String(format: "%.0f", value)
        }
        return nil
    }
}

struct PayUAuthenticationInfo: Encodable {
    let referenceId: String
    let cavv: String
    let eci: String
    let threeDSTransStatus: String
    let threeDSTransID: String
    let threeDSServerTransID: String
    let threeDSVersion: String

    init(referenceId: String, authData: PayUAuthDataResponse) {
        self.referenceId = referenceId
        cavv = authData.cavv ?? ""
        eci = authData.eci ?? ""
        threeDSTransStatus = authData.threeDSTransStatus ?? ""
        threeDSTransID = authData.threeDSTransID ?? ""
        threeDSServerTransID = authData.threeDSServerTransID ?? ""
        threeDSVersion = authData.threeDSVersion ?? ""
    }

    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PayUPaymentError.encodingFailed
        }
        return json
    }
}

// MARK: - ARes → PayU3DS2ChallengeParameter

// MARK: - Query string helper (rawBankData fallback)

enum PayUQueryStringParser {
    static func fields(from query: String?) -> [String: String] {
        guard let query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return result
    }
}

extension PayUPostToBank {

    static func from(rawBankFields: [String: String]) -> PayUPostToBank? {
        guard !rawBankFields.isEmpty else { return nil }
        return PayUPostToBank(
            referenceId: rawBankFields["referenceId"],
            eci: rawBankFields["eci"],
            threeDSServerTransID: rawBankFields["threeDSServerTransID"],
            threeDSTransID: rawBankFields["threeDSTransID"],
            threeDSTransStatus: rawBankFields["threeDSTransStatus"],
            threeDSVersion: rawBankFields["threeDSVersion"],
            threeDSTransStatusReason: rawBankFields["threeDSTransStatusReason"],
            cavv: rawBankFields["cavv"],
            acsSignedContent: rawBankFields["acsSignedContent"],
            acsReferenceNumber: rawBankFields["acsReferenceNumber"],
            acsTransID: rawBankFields["acsTransID"],
            acsRenderingType: nil,
            mfaParams: nil,
            additionalInfo: nil
        )
    }

    func makeChallengeParameter(
        cardBin: String?,
        rawBankFields: [String: String] = [:]
    ) -> PayU3DS2ChallengeParameter? {
        let signedContent = nonEmpty(acsSignedContent) ?? nonEmpty(rawBankFields["acsSignedContent"])
        let acsRefNumber = nonEmpty(acsReferenceNumber) ?? nonEmpty(rawBankFields["acsReferenceNumber"])
        let acsTransactionID = nonEmpty(acsTransID)
            ?? nonEmpty(rawBankFields["acsTransID"])
            ?? nonEmpty(threeDSTransID)
            ?? nonEmpty(rawBankFields["threeDSTransID"])
        let threeDSServerTransactionID = nonEmpty(threeDSServerTransID)
            ?? nonEmpty(rawBankFields["threeDSServerTransID"])

        guard
            let acsSignedContent = signedContent,
            let acsRefNumber,
            let acsTransactionID,
            let threeDSServerTransactionID
        else { return nil }

        let mfa: PayU3DS2MFAParam? = mfaParams.map { $0.toSDKMFAParam(cardBin: cardBin) }

        return PayU3DS2ChallengeParameter(
            acsSignedContent: acsSignedContent,
            acsRefNumber: acsRefNumber,
            acsTransactionID: acsTransactionID,
            threeDSServerTransactionID: threeDSServerTransactionID,
            mfaParams: mfa
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
