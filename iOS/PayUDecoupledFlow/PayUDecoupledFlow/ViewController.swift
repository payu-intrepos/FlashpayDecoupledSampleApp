//
//  ViewController.swift
//  PayUDecoupledFlow
//
//  Created by rishabh.jaiswal on 21/05/26.
//

import UIKit
import PayU3DS2Kit

class ViewController: UIViewController, PayU3DS2Delegate {
    func onPaymentSuccess(successResponse: Any?) {
        print("Payment success: \(String(describing: successResponse))")
    }

    func onPaymentFailure(failureResponse: Any?) {
        print("Payment failure: \(String(describing: failureResponse))")
    }

    func onPaymentCancel(isTxnInitiated: Bool) {
        print("Payment cancelled. Txn initiated: \(isTxnInitiated)")
    }

    func onError(errorCode: Int, errorMessage: String) {
        print("Error \(errorCode): \(errorMessage)")
    }
    
    func generateHash(for param: [String: String], onCompletion: @escaping PayU3DS2HashGenerationCompletion) {
        let commandName = param[PayU3DS2HashConstants.hashName] ?? ""
        let hashStringWithoutSalt = param[PayU3DS2HashConstants.hashString] ?? ""
        let hashValue = PayUHashGenerator.sha512(hashStringWithoutSalt + salt)
        onCompletion([commandName: hashValue])
    }

    @IBOutlet weak var cardHolderName: UITextField!
    @IBOutlet weak var cardExpiry: UITextField!
    @IBOutlet weak var cvvv: UITextField!
    @IBOutlet weak var cardNumber: UITextField!

    private var selectedExpiryMonth: Int?
    private var selectedExpiryYear: Int?

    // Config fields — wired up in setupProfessionalUI; pre-filled with default values.
    private var keyField: UITextField!
    private var saltField: UITextField!
    private var isProductionSwitch: UISwitch!

    /// Reads the merchant key from the UI field, falls back to the default if empty.
    var key: String {
        let v = keyField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? "<use your key>" : v
    }

    /// Reads the salt from the UI field, falls back to the default if empty.
    var salt: String {
        let v = saltField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? "<use your salt>" : v
    }

    let requestId = "\(Int(Date().timeIntervalSince1970))"

    let cardScheme: PayU3DS2Kit.PayU3DS2CardScheme = .visa
    let threeDSVersion = "2.2.0"
   

    var parqResponse: PayU3DS2PArqResponseModel?
    var paymentAPIResponse: PayUPaymentAPIResponse?

    var payUConfig: PayU3DS2Config = {
        let config = PayU3DS2Config()
        config.isProduction = false
        var textBoxCustomisation = PayU3DS2TextBoxCustomisation(
            textFontColor: "#000000",
            textFontSize: 16,
            borderColor: "#CCCCCC",
            borderWidth: 1,
            cornerRadius: 8
        )
        var uiCustomisation = PayU3DS2UICustomisation(textBoxCustomisation: textBoxCustomisation)
        config.uiCustomisation = uiCustomisation
        config.autoSubmit = false
        config.enableMFAViaBiometric = true
        config.setDefaultProgressLoader(showDefaultLoader: true, defaultProgressLoaderColor: "#1976D2")
        config.enableCustomizedOtpUIFlow = true
        config.authenticateOnly = true
        config.enableTxnTimeoutTimer = true
        config.merchantName = "Merchant Name"
        config.amount = "1"

        let acs = PayU3DS2ACSContentConfig()
        acs.submitButtonTitle = "Submit"
        acs.resendButtonTitle = "Resend"
        acs.resendInfoContent = "Resend OTP if you haven't received it"
        acs.maxResendInfoContent = "Max retries reached"
        config.acsContentConfig = acs

        return config
    }()
    private var backgroundGradientLayer: CAGradientLayer?
    private var mainScrollView: UIScrollView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupProfessionalUI()
        configureDismissKeyboardOnTap()
        configureCardInputFields()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        let keyboardHeight = keyboardFrame.height
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
        UIView.animate(withDuration: duration) {
            self.mainScrollView.contentInset = insets
            self.mainScrollView.scrollIndicatorInsets = insets
        }

        let allFields: [UITextField] = [keyField, saltField, cardNumber, cardHolderName, cardExpiry, cvvv]
        if let active = allFields.first(where: { $0.isFirstResponder }) {
            let fieldFrame = active.convert(active.bounds, to: mainScrollView)
            let targetRect = fieldFrame.insetBy(dx: 0, dy: -24)
            mainScrollView.scrollRectToVisible(targetRect, animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) else { return }
        UIView.animate(withDuration: duration) {
            self.mainScrollView.contentInset = .zero
            self.mainScrollView.scrollIndicatorInsets = .zero
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundGradientLayer?.frame = view.bounds
    }

    private func configureDismissKeyboardOnTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func configureCardInputFields() {
        cardExpiry.placeholder = "MM/YYYY"
        cardExpiry.delegate = self
        cardExpiry.inputView = UIView()
        cardExpiry.tintColor = .clear

        let expiryTap = UITapGestureRecognizer(target: self, action: #selector(cardExpiryTapped))
        cardExpiry.addGestureRecognizer(expiryTap)

        cardNumber.keyboardType = .numberPad
        cardNumber.delegate = self
        cvvv.keyboardType = .numberPad
        cvvv.delegate = self
        cardHolderName.autocapitalizationType = .words
    }

    /// Returns a user-facing error string if card number or CVV fail length rules, otherwise nil.
    private func validateCardInput() -> String? {
        let number = (cardNumber.text ?? "").filter(\.isNumber)
        let cvv = (cvvv.text ?? "").filter(\.isNumber)

        if number.count < 16 || number.count > 18 {
            return "Card number must be 16–18 digits."
        }
        if cvv.count != 3 {
            return "CVV must be exactly 3 digits."
        }
        return nil
    }

    @objc private func cardExpiryTapped() {
        view.endEditing(true)
        presentExpiryPicker()
    }

    private func presentExpiryPicker() {
        let picker = CardExpiryPickerViewController(
            initialMonth: selectedExpiryMonth,
            initialYear: selectedExpiryYear
        )
        picker.onSelect = { [weak self] month, year in
            self?.selectedExpiryMonth = month
            self?.selectedExpiryYear = year
            self?.cardExpiry.text = String(format: "%02d/%d", month, year)
        }

        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
        }
        present(picker, animated: true)
    }

    private func cardDetailsFromForm() -> PayUCardPaymentDetails? {
        let number = (cardNumber.text ?? "").filter(\.isNumber)
        let name = (cardHolderName.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cvv = (cvvv.text ?? "").filter(\.isNumber)

        guard !number.isEmpty, !name.isEmpty, !cvv.isEmpty,
              let month = selectedExpiryMonth, let year = selectedExpiryYear else {
            return nil
        }

        return PayUCardPaymentDetails(
            cardNumber: number,
            cardHolderName: name,
            cvv: cvv,
            expiryMonth: String(month),
            expiryYear: String(year)
        )
    }

    private func makePaymentParam() -> PayU3DS2PaymentParam? {
        guard let card = cardDetailsFromForm(),
              let month = selectedExpiryMonth else { return nil }

        let param = PayU3DS2PaymentParam(
            key: key,
            transactionId: requestId,
            amount: payUConfig.amount ?? "1",
            productInfo: "Phone",
            firstName: card.cardHolderName,
            email: "rishabh.jaiswal@payu.in",
            phone: "8700908382",
            surl: "https://cbjs.payu.in/sdk/success",
            furl: "https://cbjs.payu.in/sdk/failure"
        )

        let udfs = PayU3DS2UserDefines()
        udfs.udf1 = "123"
        param.udfs = udfs

        let cardDetails = PayU3DS2CardInfo()
        cardDetails.cardNumber = card.cardNumber
        cardDetails.cardName = card.cardHolderName
        cardDetails.expiryMonth = String(format: "%02d", month)
        cardDetails.expiryYear = card.expiryYear
        cardDetails.cvv = card.cvv

        param.userCredential = "smsplus:5679d3e"
        param.bankCode = "CC"
        param.pgCode = "CC"
        param.partnerWebhookSuccess = "https://cbjs.payu.in/sdk/success"
        param.partnerWebhookFailure = "https://cbjs.payu.in/sdk/failure"
        param.cardinfo = cardDetails

        return param
    }

    private func applyAPIEnvironment() {
        let environment: PayUAPIEnvironment = (isProductionSwitch?.isOn ?? false) ? .production : .test
        PayUPaymentAPIService.shared.environment = environment
        PayUAuthenticationAPIService.shared.environment = environment
    }

    @IBAction func decoupledFlow(_ sender: UIButton) {
        guard cardDetailsFromForm() != nil else {
            showAlert(title: "Missing details", message: "Enter card number, name, CVV, and expiry.")
            return
        }
        if let error = validateCardInput() {
            showAlert(title: "Invalid Input", message: error)
            return
        }
        payUConfig.isProduction = isProductionSwitch?.isOn ?? false
        applyAPIEnvironment()
        mfaInitialisation()
    }

    @IBAction func coupledFlow(_ sender: UIButton) {
        guard let paymentParam = makePaymentParam() else {
            showAlert(title: "Missing details", message: "Enter card number, name, CVV, and expiry.")
            return
        }
        if let error = validateCardInput() {
            showAlert(title: "Invalid Input", message: error)
            return
        }
        payUConfig.isProduction = isProductionSwitch?.isOn ?? false
        applyAPIEnvironment()
        PayU3DS2.initiatePayment(
            vc: self,
            config: payUConfig,
            paymentParams: paymentParam,
            delegate: self
        )
    }

    private func mfaInitialisation() {
        PayU3DS2.initialise(key: key, requestId: requestId, config: payUConfig) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                if status.status == 0 {
                    self.deviceDetails()
                } else {
                    self.showAlert(
                        title: "SDK Init Failed",
                        message: status.errorMessage ?? "Could not initialise PayU 3DS2 SDK."
                    )
                }
            }
        }
    }

    func deviceDetails() {
        let cardData = PayU3DS2CardData(cardScheme: cardScheme, threeDSVersion: threeDSVersion)
        let deviceDetails = PayU3DS2.extractDeviceDetails(cardData: cardData)

        guard deviceDetails.status == 0,
              let sdkPArq = deviceDetails.result as? PayU3DS2Kit.PayU3DS2PArqResponse else {
            showAlert(
                title: "Device Details Failed",
                message: deviceDetails.errorMessage ?? "Could not extract device details for 3DS."
            )
            return
        }

        parqResponse = PayU3DS2PArqResponseModel(sdkResponse: sdkPArq)
        initiateDecoupledPayment()
    }

    func initiateDecoupledPayment() {
        guard let parqResponse,
              let card = cardDetailsFromForm() else { return }

        let request = PayUPaymentRequest.decoupled(
            merchantKey: key,
            salt: salt,
            parq: parqResponse,
            card: card,
            txnid: requestId
        )

        Loader.shared.show(on: self)
        PayUPaymentAPIService.shared.initiatePayment(request) { [weak self] result in
            DispatchQueue.main.async {
                Loader.shared.hide()
                guard let self else { return }
                switch result {
                case .success(let response):
                    self.paymentAPIResponse = response
                    self.handlePaymentResponse(response)
                case .failure(let error):
                    self.showAlert(title: "Payment API Failed", message: error.localizedDescription)
                }
            }
        }
    }

    func handlePaymentResponse(_ response: PayUPaymentAPIResponse) {
        guard response.isSuccess else {
            let message = response.message ?? response.error ?? "Payment request was not successful."
            showAlert(title: "Payment Failed", message: message)
            return
        }
        guard let challengeParameter = response.makeChallengeParameter() else {
            showAlert(title: "Challenge Failed", message: "Could not build 3DS challenge parameters from the response.")
            return
        }

        Loader.shared.show(on: self)
        PayU3DS2.initiateChallengeWithMFA(
            challengeParameter: challengeParameter,
            vc: self,
            delegate: self
        )
    }
}

// MARK: - PayU3DS2IniitateChallengeDelegate

extension ViewController: PayU3DS2IniitateChallengeDelegate {

    func onInitateChallenge(response: Any?) {
        handleInitateChallengeResponse(response as? PayU3DS2Response)
    }

    private func handleInitateChallengeResponse(_ response: PayU3DS2Response?) {
        DispatchQueue.main.async {
            if let headless = response?.result as? PayU3DS2HeadlessData {
                Loader.shared.hide()
                let vc = VerifyOTPViewController()
                vc.setupView(
                    image1: headless.issuerImage?.high,
                    image2: headless.networkImage?.high,
                    otpSentText: headless.challengeInfoText,
                    resendButtonVisible: headless.challengeInfoText != nil
                )
                vc.challengeInputParameters = PayU3DS2ACSActionParams(
                    acsRenderingType: headless.acsRenderingType,
                    acsTransactionID: headless.acsTransactionID
                )
                vc.showAlertMessage = { [weak vc] message in
                    DispatchQueue.main.async {
                        guard let vc else { return }
                        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        vc.present(alert, animated: true)
                    }
                }
                vc.onChallengeComplete = { [weak self] actionResponse in
                    self?.handleInitateChallengeResponse(actionResponse)
                }
                vc.modalPresentationStyle = .fullScreen
                self.present(vc, animated: true)
            } else {
                if let transactionStatus = (response?.result as? [String: String])?["transactionStatus"],
                   transactionStatus == "Y" {
                    Loader.shared.hide()
                    
                    if self.payUConfig.authenticateOnly {
                        self.authenticatePayment()
                    }
                } else {
                    Loader.shared.hide()
                    self.showAlert(
                        title: "Challenge",
                        message: response?.errorMessage ?? response?.result.debugDescription ?? "Failed"
                    )
                }
            }
        }
    }

    private func authenticatePayment() {
        guard let referenceId = paymentAPIResponse?.metaData?.referenceId else {
            Loader.shared.hide()
            showAlert(title: "AuthData", message: "Missing referenceId.")
            return
        }

        let txnid = paymentAPIResponse?.metaData?.txnId ?? requestId
        let amount = payUConfig.amount ?? "1"
        let date = PayUGMTDateFormatter.string(from: Date())
        let hash = PayUHashGenerator.authDataHash(
            merchantKey: key,
            referenceId: referenceId,
            salt: salt,
            date: date
        ).hashValue

        Loader.shared.show(on: self)

        PayUAuthenticationAPIService.shared.authenticateAndAuthorize(
            key: key,
            salt: salt,
            hash: hash,
            date: date,
            referenceId: referenceId,
            txnid: txnid,
            amount: amount
        ) { [weak self] result in
            DispatchQueue.main.async {
                Loader.shared.hide()
                guard let self else { return }
                switch result {
                case .success:
                    if !self.payUConfig.enableMFAViaBiometric {
                        self.showAlert(title: "Success", message: "3DS authentication completed.")
                    }
                case .failure(let error):
                    self.showAlert(title: "AuthData Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let presenter = topMostViewController()
        guard presenter.presentedViewController == nil || presenter.presentedViewController is UIAlertController else {
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private func topMostViewController() -> UIViewController {
        var controller: UIViewController = self
        while let presented = controller.presentedViewController, !(presented is UIAlertController) {
            controller = presented
        }
        return controller
    }

    /// Called for MFA registration/deregistration status.
    func mfaRegistrationStatus(response: Any?) {
        guard let mfaResponse = response as? PayU3DS2MFAResponse else { return }

        switch mfaResponse.type {
        case .registration:
            switch mfaResponse.status {
            case .initiated:
                if presentedViewController is UIAlertController {
                    presentedViewController?.dismiss(animated: false)
                }
            case .success:
                self.showAlert(title: "Success", message: "3DS authentication completed.")
            case .failed:
                print("Registration failed:", mfaResponse.message ?? "")
            @unknown default:
                break
            }
        case .deregistration:
            switch mfaResponse.status {
            case .initiated:
                print("Deregistration started")
            case .success:
                print("Deregistration successful")
            case .failed:
                print("Deregistration failed:", mfaResponse.message ?? "")
            @unknown default:
                break
            }
        @unknown default:
            break
        }
    }
}

// MARK: - UITextFieldDelegate

extension ViewController: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === cardExpiry {
            cardExpiryTapped()
            return false
        }
        return true
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        guard textField === cardNumber || textField === cvvv else { return true }

        let current = (textField.text ?? "") as NSString
        let updated = current.replacingCharacters(in: range, with: string)

        if textField === cardNumber {
            let digitsOnly = updated.filter(\.isNumber)
            return digitsOnly.count <= 18 && digitsOnly.count == updated.count
        }
        if textField === cvvv {
            let digitsOnly = updated.filter(\.isNumber)
            return digitsOnly.count <= 3 && digitsOnly.count == updated.count
        }
        return true
    }
}

// MARK: - Professional UI

extension ViewController {

    // MARK: Colours
    private var payuNavy:  UIColor { UIColor(red: 0.05, green: 0.10, blue: 0.24, alpha: 1) }
    private var payuBlue:  UIColor { UIColor(red: 0.08, green: 0.30, blue: 0.70, alpha: 1) }
    private var payuMid:   UIColor { UIColor(red: 0.10, green: 0.40, blue: 0.85, alpha: 1) }
    private var fieldBg:   UIColor { UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1) }
    private var labelGray: UIColor { UIColor(red: 0.44, green: 0.49, blue: 0.60, alpha: 1) }
    private var bodyText:  UIColor { UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1) }

    func setupProfessionalUI() {
        // Remove storyboard-generated subviews; IBOutlets are reassigned below.
        view.subviews.forEach { $0.removeFromSuperview() }

        // ── Background gradient ──────────────────────────────────────────
        let bg = CAGradientLayer()
        bg.colors  = [payuNavy.cgColor, payuBlue.cgColor, payuMid.cgColor]
        bg.locations = [0, 0.6, 1]
        bg.startPoint = CGPoint(x: 0, y: 0)
        bg.endPoint   = CGPoint(x: 1, y: 1)
        bg.frame = view.bounds
        view.layer.insertSublayer(bg, at: 0)
        backgroundGradientLayer = bg

        // ── Scroll view ──────────────────────────────────────────────────
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        mainScrollView = scrollView

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        // ── Header ───────────────────────────────────────────────────────
        let logoLabel = UILabel()
        logoLabel.text = "PayU"
        logoLabel.font = .systemFont(ofSize: 38, weight: .black)
        logoLabel.textColor = .white
        logoLabel.translatesAutoresizingMaskIntoConstraints = false

        let taglineLabel = UILabel()
        taglineLabel.text = "Secure Payment Gateway"
        taglineLabel.font = .systemFont(ofSize: 13, weight: .regular)
        taglineLabel.textColor = UIColor.white.withAlphaComponent(0.60)
        taglineLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Config card ──────────────────────────────────────────────────
        let configCard = makeRoundedCard()

        let configTitle = UILabel()
        configTitle.text = "Merchant Configuration"
        configTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        configTitle.textColor = bodyText
        configTitle.translatesAutoresizingMaskIntoConstraints = false

        let gearIcon = UIImageView(image: UIImage(systemName: "gearshape.fill"))
        gearIcon.tintColor = payuBlue
        gearIcon.contentMode = .scaleAspectFit
        gearIcon.translatesAutoresizingMaskIntoConstraints = false

        let configDivider = makeDivider()

        let kField = makePUTextField(placeholder: "Merchant Key", icon: "key.fill")
        kField.text = "smsplus"
        kField.autocorrectionType = .no
        kField.autocapitalizationType = .none
        keyField = kField

        let sField = makePUTextField(placeholder: "Salt", icon: "checkmark.seal.fill")
        sField.text = "izF09TlpX4ZOwmf9MvXijwYsBPUmxYHD"
        sField.autocorrectionType = .no
        sField.autocapitalizationType = .none
        saltField = sField

        let prodSwitch = UISwitch()
        prodSwitch.isOn = false
        prodSwitch.onTintColor = payuBlue
        prodSwitch.translatesAutoresizingMaskIntoConstraints = false
        isProductionSwitch = prodSwitch

        let prodLabel = UILabel()
        prodLabel.text = "Production Environment"
        prodLabel.font = .systemFont(ofSize: 14, weight: .regular)
        prodLabel.textColor = bodyText
        prodLabel.translatesAutoresizingMaskIntoConstraints = false

        let prodRow = UIView()
        prodRow.translatesAutoresizingMaskIntoConstraints = false
        prodRow.addSubview(prodLabel)
        prodRow.addSubview(prodSwitch)
        NSLayoutConstraint.activate([
            prodLabel.leadingAnchor.constraint(equalTo: prodRow.leadingAnchor),
            prodLabel.centerYAnchor.constraint(equalTo: prodRow.centerYAnchor),
            prodSwitch.trailingAnchor.constraint(equalTo: prodRow.trailingAnchor),
            prodSwitch.centerYAnchor.constraint(equalTo: prodRow.centerYAnchor),
            prodSwitch.leadingAnchor.constraint(greaterThanOrEqualTo: prodLabel.trailingAnchor, constant: 8),
            prodRow.heightAnchor.constraint(equalToConstant: 44),
        ])

        let configFormStack = UIStackView(arrangedSubviews: [
            makePUFormRow(title: "MERCHANT KEY", field: kField),
            makePUFormRow(title: "SALT",         field: sField),
            prodRow,
        ])
        configFormStack.axis    = .vertical
        configFormStack.spacing = 16
        configFormStack.translatesAutoresizingMaskIntoConstraints = false

        configCard.addSubview(configTitle)
        configCard.addSubview(gearIcon)
        configCard.addSubview(configDivider)
        configCard.addSubview(configFormStack)

        NSLayoutConstraint.activate([
            gearIcon.topAnchor.constraint(equalTo: configCard.topAnchor, constant: 18),
            gearIcon.trailingAnchor.constraint(equalTo: configCard.trailingAnchor, constant: -20),
            gearIcon.widthAnchor.constraint(equalToConstant: 20),
            gearIcon.heightAnchor.constraint(equalToConstant: 20),

            configTitle.centerYAnchor.constraint(equalTo: gearIcon.centerYAnchor),
            configTitle.leadingAnchor.constraint(equalTo: configCard.leadingAnchor, constant: 20),
            configTitle.trailingAnchor.constraint(lessThanOrEqualTo: gearIcon.leadingAnchor, constant: -8),

            configDivider.topAnchor.constraint(equalTo: gearIcon.bottomAnchor, constant: 12),
            configDivider.leadingAnchor.constraint(equalTo: configCard.leadingAnchor, constant: 20),
            configDivider.trailingAnchor.constraint(equalTo: configCard.trailingAnchor, constant: -20),
            configDivider.heightAnchor.constraint(equalToConstant: 1),

            configFormStack.topAnchor.constraint(equalTo: configDivider.bottomAnchor, constant: 16),
            configFormStack.leadingAnchor.constraint(equalTo: configCard.leadingAnchor, constant: 20),
            configFormStack.trailingAnchor.constraint(equalTo: configCard.trailingAnchor, constant: -20),
            configFormStack.bottomAnchor.constraint(equalTo: configCard.bottomAnchor, constant: -20),
        ])

        // ── Payment card ─────────────────────────────────────────────────
        let card = makeRoundedCard()

        let cardTitle = UILabel()
        cardTitle.text = "Enter Card Details"
        cardTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        cardTitle.textColor = bodyText
        cardTitle.translatesAutoresizingMaskIntoConstraints = false

        let shieldIcon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        shieldIcon.tintColor = payuBlue
        shieldIcon.contentMode = .scaleAspectFit
        shieldIcon.translatesAutoresizingMaskIntoConstraints = false

        let divider = makeDivider()

        let cnField  = makePUTextField(placeholder: "1234  5678  9012  3456",
                                       icon: "creditcard.fill", keyboard: .numberPad)
        let chField  = makePUTextField(placeholder: "Name on Card", icon: "person.fill")
        let expField = makePUTextField(placeholder: "MM / YYYY",    icon: "calendar")
        let cvvField = makePUTextField(placeholder: "• • •",        icon: "lock.fill", keyboard: .numberPad)

        cardNumber     = cnField
        cardHolderName = chField
        cardExpiry     = expField
        cvvv           = cvvField

        let cnRow   = makePUFormRow(title: "CARD NUMBER",     field: cnField)
        let chRow   = makePUFormRow(title: "CARDHOLDER NAME", field: chField)
        let expRow  = makePUFormRow(title: "EXPIRY DATE",     field: expField)
        let cvvRow  = makePUFormRow(title: "SECURITY CODE",   field: cvvField)

        let bottomRow = UIStackView(arrangedSubviews: [expRow, cvvRow])
        bottomRow.axis         = .horizontal
        bottomRow.spacing      = 14
        bottomRow.distribution = .fillEqually

        let formStack = UIStackView(arrangedSubviews: [cnRow, chRow, bottomRow])
        formStack.axis    = .vertical
        formStack.spacing = 20
        formStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(cardTitle)
        card.addSubview(shieldIcon)
        card.addSubview(divider)
        card.addSubview(formStack)

        NSLayoutConstraint.activate([
            shieldIcon.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            shieldIcon.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            shieldIcon.widthAnchor.constraint(equalToConstant: 22),
            shieldIcon.heightAnchor.constraint(equalToConstant: 22),

            cardTitle.centerYAnchor.constraint(equalTo: shieldIcon.centerYAnchor),
            cardTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            cardTitle.trailingAnchor.constraint(lessThanOrEqualTo: shieldIcon.leadingAnchor, constant: -8),

            divider.topAnchor.constraint(equalTo: shieldIcon.bottomAnchor, constant: 16),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            divider.heightAnchor.constraint(equalToConstant: 1),

            formStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 20),
            formStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            formStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            formStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])

        // ── Buttons ──────────────────────────────────────────────────────
        let decoupledBtn = UIButton(type: .custom)
        decoupledBtn.setTitle("Decoupled Flow", for: .normal)
        decoupledBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        decoupledBtn.setTitleColor(payuBlue, for: .normal)
        decoupledBtn.backgroundColor = .white
        decoupledBtn.layer.cornerRadius = 14
        decoupledBtn.layer.shadowColor = UIColor.black.cgColor
        decoupledBtn.layer.shadowOpacity = 0.20
        decoupledBtn.layer.shadowOffset = CGSize(width: 0, height: 6)
        decoupledBtn.layer.shadowRadius = 10
        decoupledBtn.addTarget(self, action: #selector(decoupledFlow(_:)), for: .touchUpInside)
        decoupledBtn.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        decoupledBtn.addTarget(self, action: #selector(buttonTouchUp(_:)),   for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let payuOrangeColor = UIColor(red: 0.97, green: 0.48, blue: 0.06, alpha: 1)
        let coupledBtn = UIButton(type: .custom)
        coupledBtn.setTitle("Coupled Flow", for: .normal)
        coupledBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        coupledBtn.setTitleColor(.white, for: .normal)
        coupledBtn.backgroundColor = payuOrangeColor
        coupledBtn.layer.cornerRadius = 14
        coupledBtn.layer.shadowColor = payuOrangeColor.cgColor
        coupledBtn.layer.shadowOpacity = 0.45
        coupledBtn.layer.shadowOffset = CGSize(width: 0, height: 6)
        coupledBtn.layer.shadowRadius = 10
        coupledBtn.addTarget(self, action: #selector(coupledFlow(_:)), for: .touchUpInside)
        coupledBtn.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        coupledBtn.addTarget(self, action: #selector(buttonTouchUp(_:)),   for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let btnStack = UIStackView(arrangedSubviews: [decoupledBtn, coupledBtn])
        btnStack.axis         = .horizontal
        btnStack.spacing      = 14
        btnStack.distribution = .fillEqually
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        // ── Footer ───────────────────────────────────────────────────────
        let footer = UILabel()
        footer.text          = "256-bit SSL Encrypted  •  PCI-DSS Compliant"
        footer.font          = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor     = UIColor.white.withAlphaComponent(0.40)
        footer.textAlignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false

        // ── Hierarchy ────────────────────────────────────────────────────
        [logoLabel, taglineLabel, configCard, card, btnStack, footer].forEach { contentView.addSubview($0) }

        // ── Layout ───────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Header
            logoLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            logoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            taglineLabel.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 3),
            taglineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            // Config card
            configCard.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 20),
            configCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            configCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Payment card
            card.topAnchor.constraint(equalTo: configCard.bottomAnchor, constant: 16),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Buttons
            btnStack.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 24),
            btnStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            btnStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            btnStack.heightAnchor.constraint(equalToConstant: 54),

            // Footer
            footer.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 16),
            footer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    private func makeRoundedCard() -> UIView {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius  = 20
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.18
        v.layer.shadowOffset  = CGSize(width: 0, height: 10)
        v.layer.shadowRadius  = 18
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    // MARK: - Factory helpers

    private func makePUTextField(placeholder: String,
                                  icon: String,
                                  keyboard: UIKeyboardType = .default) -> UITextField {
        let tf = UITextField()
        tf.font            = .systemFont(ofSize: 15)
        tf.textColor       = bodyText
        tf.backgroundColor = fieldBg
        tf.layer.cornerRadius = 10
        tf.keyboardType    = keyboard
        tf.translatesAutoresizingMaskIntoConstraints = false

        // Placeholder colour
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: labelGray]
        )

        // Left icon
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 42, height: 48))
        let img = UIImageView(image: UIImage(systemName: icon))
        img.tintColor      = payuBlue
        img.contentMode    = .scaleAspectFit
        img.frame          = CGRect(x: 11, y: 13, width: 20, height: 22)
        container.addSubview(img)
        tf.leftView        = container
        tf.leftViewMode    = .always

        tf.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return tf
    }

    private func makePUFormRow(title: String, field: UITextField) -> UIStackView {
        let lbl = UILabel()
        lbl.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: labelGray,
                .kern: 1.3
            ]
        )
        let stack = UIStackView(arrangedSubviews: [lbl, field])
        stack.axis    = .vertical
        stack.spacing = 7
        return stack
    }

    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.12) { sender.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) }
    }

    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 6) {
            sender.transform = .identity
        }
    }
}

