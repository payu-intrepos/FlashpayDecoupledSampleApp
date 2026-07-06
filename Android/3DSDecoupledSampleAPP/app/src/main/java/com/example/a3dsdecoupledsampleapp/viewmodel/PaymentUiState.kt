package com.example.a3dsdecoupledsampleapp.viewmodel

import com.payu.threedsbase.data.ChallengeParameter
import com.payu.threedsbase.data.PayU3DS2DeviceWarning

sealed class PaymentUiState {
    object Idle : PaymentUiState()
    data class Loading(val message: String) : PaymentUiState()
    data class Success(val message: String) : PaymentUiState()
    data class Error(val message: String) : PaymentUiState()
    data class ChallengeReady(val parameter: ChallengeParameter) : PaymentUiState()
    /** Non-blocking warning shown as a Toast (e.g. biometric registration failure). */
    data class Warning(val message: String) : PaymentUiState()
    /**
     * One or more HIGH-severity device security warnings returned by [PayU3DS2.initialise].
     * The flow is halted — merchant must decide how to proceed per their business policy.
     * Warning IDs: SW01 Rooted, SW02 SDK tampered, SW03 Emulator, SW04 Debugger, SW05 Unsupported OS.
     */
    data class DeviceWarnings(val warnings: List<PayU3DS2DeviceWarning>) : PaymentUiState()
}
