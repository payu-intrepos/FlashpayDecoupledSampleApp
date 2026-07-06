package com.example.a3dsdecoupledsampleapp.data.model

import com.payu.threedsbase.data.apiResponse.PayU3DS2MFAParam

/**
 * Holds the parsed authentication data returned from the PayU _payment API,
 * including ACS signed content needed to initiate the 3DS challenge.
 */
data class ThreeDSAuthData(
    val acsSignedContent: String,
    val acsRefNumber: String,
    val acsTransactionId: String,
    val threeDSServerTransactionId: String,
    val threeDSTransactionStatus: String?,
    val cavv: String?,
    val mfaParam: PayU3DS2MFAParam?
)
