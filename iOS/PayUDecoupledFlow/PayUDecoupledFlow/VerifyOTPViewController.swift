//
//  VerifyOTPViewController.swift
//  PayUDecoupledFlow
//

import UIKit
import PayU3DS2Kit

final class VerifyOTPViewController: UIViewController {

    var challengeInputParameters: PayU3DS2ACSActionParams?
    var showAlertMessage: ((String) -> Void)?
    var onChallengeComplete: ((PayU3DS2Response) -> Void)?

    private let issuerImageView = UIImageView()
    private let networkImageView = UIImageView()
    private let otpInfoLabel = UILabel()
    private let otpTextField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let resendButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        resendButton.addTarget(self, action: #selector(resendTapped), for: .touchUpInside)
    }

    func setupView(
        image1: String?,
        image2: String?,
        otpSentText: String?,
        resendButtonVisible: Bool
    ) {
        loadImage(urlString: image1, into: issuerImageView)
        loadImage(urlString: image2, into: networkImageView)
        otpInfoLabel.text = otpSentText ?? "Enter OTP"
        resendButton.isHidden = !resendButtonVisible
    }

    private func setupLayout() {
        [issuerImageView, networkImageView, otpInfoLabel, otpTextField, submitButton, resendButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        issuerImageView.contentMode = .scaleAspectFit
        networkImageView.contentMode = .scaleAspectFit
        otpInfoLabel.numberOfLines = 0
        otpInfoLabel.textAlignment = .center

        otpTextField.borderStyle = .roundedRect
        otpTextField.keyboardType = .numberPad
        otpTextField.placeholder = "OTP"

        submitButton.setTitle("Submit", for: .normal)
        resendButton.setTitle("Resend", for: .normal)

        NSLayoutConstraint.activate([
            issuerImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            issuerImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            issuerImageView.widthAnchor.constraint(equalToConstant: 80),
            issuerImageView.heightAnchor.constraint(equalToConstant: 50),

            networkImageView.topAnchor.constraint(equalTo: issuerImageView.bottomAnchor, constant: 12),
            networkImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            networkImageView.widthAnchor.constraint(equalToConstant: 80),
            networkImageView.heightAnchor.constraint(equalToConstant: 50),

            otpInfoLabel.topAnchor.constraint(equalTo: networkImageView.bottomAnchor, constant: 24),
            otpInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            otpInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            otpTextField.topAnchor.constraint(equalTo: otpInfoLabel.bottomAnchor, constant: 16),
            otpTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            otpTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            otpTextField.heightAnchor.constraint(equalToConstant: 44),

            submitButton.topAnchor.constraint(equalTo: otpTextField.bottomAnchor, constant: 24),
            submitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            resendButton.topAnchor.constraint(equalTo: submitButton.bottomAnchor, constant: 16),
            resendButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func submitTapped() {
        performAction(.submit)
    }

    @objc private func resendTapped() {
        performAction(.resend)
    }

    private func performAction(_ actionType: PayU3DS2ACSActionType) {
        guard let params = challengeInputParameters else { return }
        params.challengeData = otpTextField.text

        Loader.shared.show(on: self)
        PayU3DS2.action(acsActionType: actionType, challengeInputParams: params) { [weak self] response in
            DispatchQueue.main.async {
                Loader.shared.hide()
                guard let self else { return }
                if response.status == 0 {
                    self.dismiss(animated: true) {
                        self.onChallengeComplete?(response)
                    }
                } else {
                    self.showAlertMessage?(response.errorMessage ?? "OTP action failed")
                }
            }
        }
    }

    private func loadImage(urlString: String?, into imageView: UIImageView) {
        guard let urlString, let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { imageView.image = image }
        }.resume()
    }
}
