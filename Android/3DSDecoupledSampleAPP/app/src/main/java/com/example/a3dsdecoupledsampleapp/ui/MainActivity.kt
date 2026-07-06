package com.example.a3dsdecoupledsampleapp.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.a3dsdecoupledsampleapp.R
import com.example.a3dsdecoupledsampleapp.viewmodel.PaymentUiState
import com.example.a3dsdecoupledsampleapp.viewmodel.PaymentViewModel
import com.payu.threedsbase.data.PayU3DS2DeviceWarning
import com.google.android.material.textfield.TextInputEditText
import com.payu.threeDS2.PayU3DS2

class MainActivity : AppCompatActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    private val viewModel: PaymentViewModel by viewModels()

    private lateinit var etMerchantKey:    TextInputEditText
    private lateinit var etMerchantSalt:   TextInputEditText
    private lateinit var etMerchantName:   TextInputEditText
    private lateinit var rgEnvironment:    RadioGroup
    private lateinit var etAmount:         TextInputEditText
    private lateinit var etFirstName:      TextInputEditText
    private lateinit var etLastName:       TextInputEditText
    private lateinit var etEmail:          TextInputEditText
    private lateinit var etPhoneNumber:    TextInputEditText
    private lateinit var etCardNumber:     TextInputEditText
    private lateinit var etExpiry:         TextInputEditText
    private lateinit var etCvv:            TextInputEditText
    private lateinit var etCardholderName: TextInputEditText
    private lateinit var btnPay:           Button
    private lateinit var loadingOverlay:   LinearLayout
    private lateinit var tvLoadingStatus:  TextView

    private val merchantKey  get() = etMerchantKey.text?.toString()?.trim().orEmpty()
    private val merchantSalt get() = etMerchantSalt.text?.toString()?.trim().orEmpty()
    private val merchantName get() = etMerchantName.text?.toString()?.trim().orEmpty()
    private val isUat        get() = rgEnvironment.checkedRadioButtonId == R.id.rbUat
    private val amount       get() = etAmount.text?.toString()?.trim().orEmpty().ifBlank { "100.00" }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        etMerchantKey    = findViewById(R.id.etMerchantKey)
        etMerchantSalt   = findViewById(R.id.etMerchantSalt)
        etMerchantName   = findViewById(R.id.etMerchantName)
        rgEnvironment    = findViewById(R.id.rgEnvironment)
        etAmount         = findViewById(R.id.etAmount)
        etFirstName      = findViewById(R.id.etFirstName)
        etLastName       = findViewById(R.id.etLastName)
        etEmail          = findViewById(R.id.etEmail)
        etPhoneNumber    = findViewById(R.id.etPhoneNumber)
        etCardNumber     = findViewById(R.id.etCardNumber)
        etExpiry         = findViewById(R.id.etExpiry)
        etCvv            = findViewById(R.id.etCvv)
        etCardholderName = findViewById(R.id.etCardholderName)
        btnPay           = findViewById(R.id.btnPay)
        loadingOverlay   = findViewById(R.id.loadingOverlay)
        tvLoadingStatus  = findViewById(R.id.tvLoadingStatus)

        etAmount.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val amt = s?.toString()?.trim()?.ifBlank { "0.00" } ?: "0.00"
                btnPay.text = "Pay ₹$amt Securely"
            }
        })

        btnPay.setOnClickListener { onPayClicked() }
        observeUiState()
        requestRequiredPermissions()
    }

    private fun observeUiState() {
        viewModel.uiState.observe(this) { state ->
            // Dismiss the loading overlay for every state except Loading itself.
            // This guarantees the overlay never gets stuck regardless of which state
            // follows a Loading — no individual branch needs to remember to hide it.
            if (state !is PaymentUiState.Loading) {
                loadingOverlay.visibility = View.GONE
            }

            when (state) {
                is PaymentUiState.Idle -> {
                    btnPay.isEnabled = true
                }
                is PaymentUiState.Loading -> {
                    loadingOverlay.visibility = View.VISIBLE
                    tvLoadingStatus.text = state.message
                    btnPay.isEnabled = false
                }
                is PaymentUiState.ChallengeReady -> {
                    btnPay.isEnabled = true
                    PayU3DS2.initiateChallengeWithMFA(this, state.parameter, viewModel.mfaCallback)
                }
                is PaymentUiState.Success -> {
                    btnPay.isEnabled = true
                    showResultDialog(success = true, message = state.message)
                }
                is PaymentUiState.Error -> {
                    btnPay.isEnabled = true
                    showResultDialog(success = false, message = state.message)
                }
                is PaymentUiState.Warning -> {
                    // Re-enable Pay so the user can proceed after biometric/SIM
                    // registration completes (SUCCESS or FAILED). The terminal result
                    // (onSuccess / onError) will update the button state once the
                    // full challenge concludes.
                    btnPay.isEnabled = true
                    Toast.makeText(this, state.message, Toast.LENGTH_LONG).show()
                }
                is PaymentUiState.DeviceWarnings -> {
                    btnPay.isEnabled = true
                    showDeviceWarningsDialog(state.warnings)
                }
            }
        }
    }

    private fun onPayClicked() {
        val key          = merchantKey
        val salt         = merchantSalt
        val name         = merchantName
        val firstName    = etFirstName.text?.toString()?.trim().orEmpty()
        val lastName     = etLastName.text?.toString()?.trim().orEmpty()
        val email        = etEmail.text?.toString()?.trim().orEmpty()
        val phoneNumber  = etPhoneNumber.text?.toString()?.trim().orEmpty()
        val cardNumber   = etCardNumber.text?.toString()?.filter { it.isDigit() }.orEmpty()
        val expiry       = etExpiry.text?.toString()?.trim().orEmpty()
        val cvv          = etCvv.text?.toString()?.trim().orEmpty()
        val holderName   = etCardholderName.text?.toString()?.trim().orEmpty()

        if (key.isBlank() || salt.isBlank()) {
            Toast.makeText(this, "Please enter Merchant Key and Salt", Toast.LENGTH_SHORT).show()
            return
        }
        if (firstName.isBlank() || email.isBlank() || phoneNumber.isBlank()) {
            Toast.makeText(this, "Please fill all customer details", Toast.LENGTH_SHORT).show()
            return
        }
        if (cardNumber.length < 13 || cvv.length < 3 || expiry.length < 4) {
            Toast.makeText(this, "Please fill all card details", Toast.LENGTH_SHORT).show()
            return
        }

        val expiryMonth = expiry.take(2)
        val expiryYear  = if (expiry.length >= 5) "20${expiry.takeLast(2)}" else expiry.takeLast(4)

        viewModel.startPayment(
            activity       = this,
            merchantKey    = key,
            merchantSalt   = salt,
            merchantName   = name,
            amount         = amount,
            firstName   = firstName,
            lastName    = lastName,
            email       = email,
            phoneNumber = phoneNumber,
            cardNumber     = cardNumber,
            expiryMonth    = expiryMonth,
            expiryYear     = expiryYear,
            cvv            = cvv,
            cardholderName = holderName,
            isUat          = isUat
        )
    }

    /**
     * Shows a blocking dialog for HIGH-severity device security warnings returned by SDK init.
     * Handle per your business policy — e.g. deny payment on a rooted or emulator device.
     */
    private fun showDeviceWarningsDialog(warnings: List<PayU3DS2DeviceWarning>) {
        val warningText = warnings.joinToString("\n\n") { warning ->
            "[${warning.id}] ${warning.message} (Severity: ${warning.severity})"
        }
        AlertDialog.Builder(this)
            .setTitle("⚠️ Device Security Warnings")
            .setMessage(
                "The following security checks failed on this device.\n\n$warningText\n\n" +
                "Handle these per your business policy (e.g. block on HIGH severity)."
            )
            .setPositiveButton("OK", null)
            .show()
    }

    private fun showResultDialog(success: Boolean, message: String) {
        val emoji = if (success) "✅" else "❌"
        val title = if (success) "Payment Successful" else "Payment Failed"
        AlertDialog.Builder(this)
            .setTitle("$emoji $title")
            .setMessage(message)
            .setPositiveButton("OK", null)
            .show()
    }

    private fun requestRequiredPermissions() {
        val required = buildList {
            add(Manifest.permission.READ_PHONE_STATE)
            add(Manifest.permission.SEND_SMS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        val needed = required.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val denied = permissions.filterIndexed { i, _ ->
                grantResults.getOrElse(i) { PackageManager.PERMISSION_DENIED } != PackageManager.PERMISSION_GRANTED
            }
            if (denied.isNotEmpty()) {
                Toast.makeText(
                    this,
                    "Please allow all permissions for biometric MFA to work",
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }
}
