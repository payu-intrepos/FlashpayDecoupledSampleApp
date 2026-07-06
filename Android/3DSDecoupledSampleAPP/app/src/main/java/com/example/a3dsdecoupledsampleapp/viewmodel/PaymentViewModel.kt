package com.example.a3dsdecoupledsampleapp.viewmodel

import android.app.Activity
import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.a3dsdecoupledsampleapp.data.repository.PaymentRepository
import com.example.a3dsdecoupledsampleapp.utils.JsonUtils
import com.example.a3dsdecoupledsampleapp.utils.ThreeDSRequestBuilder
import com.payu.threeDS2.PayU3DS2
import com.payu.threeDS2.config.PayU3DS2Config
import com.payu.threedsbase.config.PayU3DS2MFAResponse
import com.payu.threedsbase.data.PayU3DS2DeviceWarning
import com.payu.threedsbase.enums.CardScheme
import com.payu.threedsbase.enums.PayU3DS2MFARequestType
import com.payu.threedsbase.enums.PayU3DS2MFAStatus
import com.payu.threedsbase.interfaces.listeners.PayU3DS2MFACallback
import com.payu.threedsui.uiCustomisation.ButtonCustomisation
import com.payu.threedsui.uiCustomisation.LabelCustomisation
import com.payu.threedsui.uiCustomisation.TextBoxCustomisation
import com.payu.threedsui.uiCustomisation.ToolbarCustomisation
import com.payu.threedsui.uiCustomisation.UICustomisation
import kotlinx.coroutines.launch
import java.util.UUID

class PaymentViewModel(
    private val repository: PaymentRepository = PaymentRepository()
) : ViewModel() {

    companion object {
        private const val TAG = "PaymentViewModel"
    }

    private val _uiState = MutableLiveData<PaymentUiState>(PaymentUiState.Idle)
    val uiState: LiveData<PaymentUiState> = _uiState

    val mfaCallback = object : PayU3DS2MFACallback {

        /**
         * Called when challenge completes. The response HashMap always contains
         * "transactionStatus" and optionally "mfaRegistrationStatus".
         */
        override fun onSuccess(response: Any) {
            if (response !is HashMap<*, *>) {
                Log.w(TAG, "onSuccess: unexpected response type ${response::class.simpleName}")
                _uiState.postValue(PaymentUiState.Error("Unexpected challenge response format."))
                return
            }
            val transactionStatus = response["transactionStatus"] as? String
            val embeddedMfa       = response["mfaRegistrationStatus"] as? PayU3DS2MFAResponse
            if (embeddedMfa != null) {
                mfaRegistrationStatus(embeddedMfa)
            }
            if (transactionStatus == "Y") {
                _uiState.postValue(PaymentUiState.Success("Payment Authenticated Successfully!"))
            } else {
                _uiState.postValue(PaymentUiState.Error("Authentication status: $transactionStatus"))
            }
        }

        /**
         * Maps SDK error codes to user-friendly messages per the FlashPay 3DS spec error table.
         */
        override fun onError(errorCode: Int, errorMessage: String) {
            val userMessage = when (errorCode) {
                3    -> "Authentication timed out. Please try again."
                5    -> "Authentication was cancelled."
                14   -> "OTP resend limit reached. Please try again later."
                15   -> "Incorrect OTP entered. Please retry."
                17   -> "Transaction failed. Please try again."
                32   -> "Device deregistered."
                33   -> "Biometric authentication error. Please use OTP."
                34   -> "Biometric registration failed."
                103  -> "Invalid amount format."
                104  -> "Transaction ID is missing."
                else -> "Authentication failed [$errorCode]: $errorMessage"
            }
            _uiState.postValue(PaymentUiState.Error(userMessage))
        }

        /**
         * Handles all 6 biometric MFA registration states:
         * REGISTRATION x (INITIATED / SUCCESS / FAILED)
         * DEREGISTRATION x (INITIATED / SUCCESS / FAILED)
         */
        override fun mfaRegistrationStatus(response: Any?) {
            val mfaResponse = response as? PayU3DS2MFAResponse ?: return
            when (mfaResponse.type) {
                PayU3DS2MFARequestType.REGISTRATION -> when (mfaResponse.status) {
                    PayU3DS2MFAStatus.INITIATED -> _uiState.postValue(
                        PaymentUiState.Loading("Registering biometric... (timeout: ${mfaResponse.timeout}s)")
                    )
                    PayU3DS2MFAStatus.SUCCESS -> _uiState.postValue(
                        PaymentUiState.Warning("Biometric registered successfully.")
                    )
                    PayU3DS2MFAStatus.FAILED -> _uiState.postValue(
                        PaymentUiState.Warning("Biometric registration failed: ${mfaResponse.message}")
                    )
                }
                PayU3DS2MFARequestType.DEREGISTRATION -> when (mfaResponse.status) {
                    PayU3DS2MFAStatus.INITIATED -> _uiState.postValue(
                        PaymentUiState.Loading("Deregistering biometric...")
                    )
                    PayU3DS2MFAStatus.SUCCESS -> _uiState.postValue(
                        PaymentUiState.Warning("Biometric deregistered: ${mfaResponse.message}")
                    )
                    PayU3DS2MFAStatus.FAILED -> _uiState.postValue(
                        PaymentUiState.Warning("Deregistration failed: ${mfaResponse.message}")
                    )
                }
            }
        }
    }

    fun startPayment(
        activity: Activity,
        merchantKey: String,
        merchantSalt: String,
        merchantName: String,
        amount: String,
        firstName: String,
        lastName: String,
        email: String,
        phoneNumber: String,
        cardNumber: String,
        expiryMonth: String,
        expiryYear: String,
        cvv: String,
        cardholderName: String,
        isUat: Boolean
    ) {
        val transactionId   = "TXN${UUID.randomUUID().toString().replace("-", "").take(20)}"
        val cardScheme      = if (cardNumber.startsWith("4")) CardScheme.VISA else CardScheme.MASTERCARD
        val sdkMerchantName = merchantName

        _uiState.value = PaymentUiState.Loading("Initialising...")

        viewModelScope.launch {
            try {
                // Step 1 — Initialise SDK
                val sdkConfig = PayU3DS2Config().apply {
                    isProduction              = !isUat
                    fallback3DS1              = true
                    autoSubmit                = false
                    autoRead                  = false
                    enableMFAViaBiometric     = true
                    enableCustomizedOtpUIFlow = true
                    enableTxnTimeoutTimer     = true
                    authenticateOnly          = false  // set true for auth-only flow
                    this.merchantName         = sdkMerchantName
                    this.amount               = amount
                    setDefaultProgressLoader(true, "#1A1A2E")

                    // Uncomment and customise to match your brand:
                     uiCustomisation = buildUiCustomisation()
                }
                val initResult = PayU3DS2.initialise(merchantKey, transactionId, activity, sdkConfig)
                if (initResult.status != 0) throw Exception("SDK initialisation failed: ${initResult.errorMessage}")

                // Read device security warnings from SDK initialisation result.
                // HIGH-severity warnings indicate rooted device, tampering, emulator, debugger,
                // or unsupported OS. Block or allow per your business policy.
                val deviceWarnings = (initResult.result as? List<*>)
                    ?.filterIsInstance<PayU3DS2DeviceWarning>()
                    .orEmpty()
                val highSeverityWarnings = deviceWarnings.filter {
                    it.severity?.toString().equals("HIGH", ignoreCase = true)
                }
                if (highSeverityWarnings.isNotEmpty()) {
                    _uiState.value = PaymentUiState.DeviceWarnings(highSeverityWarnings)
                    return@launch
                }
                deviceWarnings.forEach { warning ->
                    Log.w(TAG, "Device warning [${warning.id}] ${warning.severity}: ${warning.message}")
                }

                // Step 2 — Card BIN lookup (non-critical: failure falls back to card number prefix)
                _uiState.value = PaymentUiState.Loading("Fetching card info...")
                val binInfoResponse = runCatching {
                    repository.fetchBinInfo(cardNumber, merchantSalt)
                }.onFailure { error ->
                    Log.w(TAG, "BIN lookup failed, falling back to card prefix: ${error.message}")
                }.getOrNull()

                // Guard: this SDK handles 3DS 2.x only — redirect flow needed for 3DS 1.x cards.
                val messageVersion = binInfoResponse?.messageVersion
                if (messageVersion != null && messageVersion.startsWith("1.")) {
                    throw Exception(
                        "Card supports 3DS 1.0 only (version: $messageVersion). " +
                        "Use the redirect flow instead of this decoupled SDK."
                    )
                }

                // Step 3 — Device fingerprinting (passes threeDSVersion from BIN info)
                _uiState.value = PaymentUiState.Loading("Preparing device info...")
                val authRequestData = repository.extractDeviceDetails(cardScheme, messageVersion)

                // Step 4 — Submit payment with 3DS2 data
                _uiState.value = PaymentUiState.Loading("Authenticating card...")
                val threeDS2RequestData = ThreeDSRequestBuilder.buildRequest(authRequestData)
                val paymentRequest = repository.buildPaymentParams(
                    merchantKey         = merchantKey,
                    transactionId       = transactionId,
                    amount              = amount,
                    firstName   = firstName,
                    lastName    = lastName,
                    email       = email,
                    phoneNumber = phoneNumber,
                    cardholderName      = cardholderName,
                    cardNumber          = cardNumber,
                    expiryMonth         = expiryMonth,
                    expiryYear          = expiryYear,
                    cvv                 = cvv,
                    threeDS2RequestData = threeDS2RequestData,
                    isUat               = isUat
                )
                val paymentResponse = repository.callPaymentsApi(paymentRequest, merchantSalt)

                // Step 5 — Parse response and launch challenge
                _uiState.value = PaymentUiState.Loading("Launching 3DS challenge...")
                val cardBin  = binInfoResponse?.bin ?: cardNumber.take(6)
                val authData = repository.parseAuthResponse(paymentResponse, cardBin)
                    ?: throw Exception(
                        "Could not parse ACS challenge data.\n${JsonUtils.describeFailure(paymentResponse)}"
                    )

                val isFrictionless = authData.threeDSTransactionStatus == "Y" &&
                    !authData.cavv.isNullOrBlank() &&
                    authData.acsSignedContent.isBlank()

                if (isFrictionless) {
                    _uiState.value = PaymentUiState.Success("Payment Authorised (Frictionless 3DS)")
                    return@launch
                }

                _uiState.value = PaymentUiState.ChallengeReady(
                    repository.buildChallengeParameter(authData)
                )

            } catch (e: Exception) {
                _uiState.value = PaymentUiState.Error(e.message ?: "Payment failed")
            }
        }
    }

    // Uncomment and customise to match your brand — plug into sdkConfig.uiCustomisation above.
    //
     private fun buildUiCustomisation(): UICustomisation {
         val button  = ButtonCustomisation.Builder().setBackgroundColor("#1D4ED8").setCornerRadius(12).build()
         val toolbar = ToolbarCustomisation.Builder().setBackgroundColor("#0F172A").setHeaderText("Secure Payment").build()
         val label   = LabelCustomisation.Builder().setHeadingTextColor("#0F172A").setTextColor("#475569").build()
         val textBox = TextBoxCustomisation.Builder().setBorderColor("#CBD5E1").setCornerRadius(10).build()
         return UICustomisation.Builder()
             .setButtonCustomisation(button)
             .setToolbarCustomisation(toolbar)
             .setLabelCustomisation(label)
             .setTextBoxCustomisation(textBox)
             .build()
     }
}
