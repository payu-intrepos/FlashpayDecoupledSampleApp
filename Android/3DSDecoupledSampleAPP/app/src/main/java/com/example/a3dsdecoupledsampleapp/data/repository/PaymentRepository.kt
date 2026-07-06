package com.example.a3dsdecoupledsampleapp.data.repository

import com.example.a3dsdecoupledsampleapp.data.model.PaymentRequest
import com.example.a3dsdecoupledsampleapp.data.model.ThreeDSAuthData
import com.example.a3dsdecoupledsampleapp.network.NetworkConstants
import com.example.a3dsdecoupledsampleapp.network.PaymentApiService
import com.example.a3dsdecoupledsampleapp.utils.HashUtils
import com.example.a3dsdecoupledsampleapp.utils.JsonUtils
import com.google.gson.JsonObject
import com.payu.threeDS2.PayU3DS2
import com.payu.threedsbase.data.CardData
import com.payu.threedsbase.data.ChallengeParameter
import com.payu.threedsbase.data.PArqResponse
import com.payu.threedsbase.data.apiRequest.CardBinInfoRequest
import com.payu.threedsbase.data.apiResponse.BinInfoResponse
import com.payu.threedsbase.data.apiResponse.PayU3DS2MFAParam
import com.payu.threedsbase.enums.CardScheme
import com.payu.threedsbase.interfaces.listeners.PayU3DS2Callback
import com.payu.threedsbase.interfaces.listeners.PayUHashGeneratedListener
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class PaymentRepository(
    private val apiService: PaymentApiService = PaymentApiService()
) {

    suspend fun fetchBinInfo(cardNumber: String, merchantSalt: String): BinInfoResponse? =
        suspendCancellableCoroutine { continuation ->
            PayU3DS2.cardBinInfo(
                CardBinInfoRequest(cardDetails = cardNumber, isSI = true),
                object : PayU3DS2Callback {
                    override fun generateHash(
                        map: HashMap<String, String>,
                        hashGenerationListener: PayUHashGeneratedListener
                    ) {
                        val hashName = map["hashName"] ?: return
                        val hashString = map["hashString"] ?: ""
                        val postSalt = map["postSalt"] ?: ""
                        hashGenerationListener.onHashGenerated(
                            hashMapOf(hashName to HashUtils.sha512(hashString + merchantSalt + postSalt))
                        )
                    }

                    override fun onSuccess(response: Any) {
                        if (continuation.isActive) continuation.resume(response as? BinInfoResponse)
                    }

                    override fun onError(errorCode: Int, errorMessage: String) {
                        if (continuation.isActive) continuation.resumeWithException(
                            Exception("[$errorCode] $errorMessage")
                        )
                    }
                }
            )
        }

    /**
     * Runs on [Dispatchers.Default] — device fingerprinting involves cryptographic
     * operations that are CPU-bound and should not block the Main thread.
     *
     * @param threeDSVersion The 3DS version from BIN info (e.g. "2.1.0"). Passed to [CardData]
     *   so the SDK can tailor the device fingerprint to the correct protocol version.
     *   May be null when BIN lookup was unavailable; the SDK will use its default version.
     */
    suspend fun extractDeviceDetails(
        cardScheme: CardScheme,
        threeDSVersion: String?
    ): PArqResponse =
        withContext(Dispatchers.Default) {
            // CardData always requires a non-null cardScheme.
            // threeDSVersion is set only when the BIN lookup returned a value — the SDK
            // rejects an explicit null but handles the absent field gracefully.
            val cardData = CardData(cardScheme = cardScheme).apply {
                threeDSVersion?.let { this.threeDSVersion = it }
            }
            val deviceResult = PayU3DS2.extractDeviceDetails(cardData)
            if (deviceResult.status != 0) throw Exception("Device details failed: ${deviceResult.errorMessage}")
            deviceResult.result as? PArqResponse
                ?: throw Exception("PArqResponse is null")
        }

    fun buildPaymentParams(
        merchantKey: String,
        transactionId: String,
        amount: String,
        firstName: String,
        lastName: String,
        email: String,
        phoneNumber: String,
        cardholderName: String,
        cardNumber: String,
        expiryMonth: String,
        expiryYear: String,
        cvv: String,
        threeDS2RequestData: String,
        isUat: Boolean
    ): PaymentRequest {
        val baseUrl = if (isUat) NetworkConstants.UAT_BASE_URL else NetworkConstants.PROD_BASE_URL
        val params = linkedMapOf(
            "key" to merchantKey,
            "txnid" to transactionId,
            "amount" to amount,
            "productinfo" to "Test Product",
            "firstname" to firstName,
            "lastname" to lastName,
            "email" to email,
            "phone" to phoneNumber,
            "pg" to "CC",
            "bankcode" to "CC",
            "ccnum" to cardNumber,
            "ccname" to cardholderName,
            "ccexpmon" to expiryMonth,
            "ccexpyr" to expiryYear,
            "ccvv" to cvv,
            "surl" to NetworkConstants.SUCCESS_URL,
            "furl" to NetworkConstants.FAILURE_URL,
            "txn_s2s_flow" to "4",
            "auth_only" to "2",
            "threeds_authN_flow" to "2",
            "termUrl" to NetworkConstants.TERM_URL,
            "threeDS2RequestData" to threeDS2RequestData,
        )
        return PaymentRequest(params = params, baseUrl = baseUrl)
    }

    suspend fun callPaymentsApi(request: PaymentRequest, salt: String): JsonObject =
        apiService.callPaymentsApi(request.params, salt, request.baseUrl)

    fun parseAuthResponse(json: JsonObject, cardBin: String? = null): ThreeDSAuthData? {
        val resultElement = json.get("result")
        if (resultElement == null || !resultElement.isJsonObject) return null
        val result = resultElement.asJsonObject

        val challengeData = when {
            result.has("postToBank") && result["postToBank"].isJsonObject ->
                result.getAsJsonObject("postToBank")

            else -> result
        }

        val requiredChallengeFields = listOf(
            "acsSignedContent", "acsTransID", "threeDSServerTransID", "acsReferenceNumber"
        )
        if (requiredChallengeFields.none {
                !JsonUtils.getStringOrNull(challengeData, it).isNullOrBlank()
            }) return null

        return ThreeDSAuthData(
            acsSignedContent = JsonUtils.getStringOrNull(challengeData, "acsSignedContent")
                .orEmpty(),
            acsRefNumber = JsonUtils.getStringOrNull(challengeData, "acsReferenceNumber").orEmpty(),
            acsTransactionId = JsonUtils.getStringOrNull(challengeData, "acsTransID").orEmpty(),
            threeDSServerTransactionId = JsonUtils.getStringOrNull(
                challengeData,
                "threeDSServerTransID"
            ).orEmpty(),
            threeDSTransactionStatus = JsonUtils.getStringOrNull(
                challengeData,
                "threeDSTransStatus"
            ),
            cavv = JsonUtils.getStringOrNull(challengeData, "cavv"),
            mfaParam = parseMfaParam(challengeData, cardBin)
        )
    }

    private fun parseMfaParam(
        challengeData: JsonObject,
        cardBin: String? = null
    ): PayU3DS2MFAParam? {
        val mfaElement = challengeData.get("mfaParams")
        if (mfaElement == null || !mfaElement.isJsonObject) return null
        val mfa = mfaElement.asJsonObject
        return PayU3DS2MFAParam().apply {
            messageType = JsonUtils.getStringOrNull(mfa, "messageType")
            name = JsonUtils.getStringOrNull(mfa, "name")
            id = JsonUtils.getStringOrNull(mfa, "id")
            criticalityIndicator = mfa.get("criticalityIndicator")?.asBoolean ?: false
            issuerImage = JsonUtils.getStringOrNull(mfa, "issuerImage")
            psImage = JsonUtils.getStringOrNull(mfa, "psImage")
            tdyClientId = JsonUtils.getStringOrNull(mfa, "tdyClientId")
            tdyCardId = JsonUtils.getStringOrNull(mfa, "tdyCardId")
            data = JsonUtils.getStringOrNull(mfa, "data")
            this.cardBin = JsonUtils.getStringOrNull(mfa, "cardBin") ?: cardBin
        }
    }

    fun buildChallengeParameter(authData: ThreeDSAuthData): ChallengeParameter =
        ChallengeParameter(
            acsSignedContent = authData.acsSignedContent,
            acsRefNumber = authData.acsRefNumber,
            acsTransactionID = authData.acsTransactionId,
            threeDSServerTransactionID = authData.threeDSServerTransactionId,
            payU3DS2MfaParam = authData.mfaParam
        )
}
