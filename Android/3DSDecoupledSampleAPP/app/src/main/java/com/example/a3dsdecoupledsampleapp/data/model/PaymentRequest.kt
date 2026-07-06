package com.example.a3dsdecoupledsampleapp.data.model

/**
 * Encapsulates the payment form parameters and the target base URL
 * ready to be submitted to the PayU _payment API.
 */
data class PaymentRequest(
    val params: LinkedHashMap<String, String>,
    val baseUrl: String
)
