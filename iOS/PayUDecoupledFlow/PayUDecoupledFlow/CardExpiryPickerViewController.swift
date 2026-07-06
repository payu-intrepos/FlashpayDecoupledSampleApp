//
//  CardExpiryPickerViewController.swift
//  PayUDecoupledFlow
//

import UIKit

final class CardExpiryPickerViewController: UIViewController {

    var onSelect: ((Int, Int) -> Void)?

    private let months = Array(1 ... 12)
    private lazy var years: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear ... (currentYear + 20))
    }()

    private var selectedMonth = Calendar.current.component(.month, from: Date())
    private var selectedYear: Int

    private let picker = UIPickerView()
    private let toolbar = UIToolbar()

    init(initialMonth: Int? = nil, initialYear: Int? = nil) {
        let now = Date()
        let calendar = Calendar.current
        selectedMonth = initialMonth ?? calendar.component(.month, from: now)
        selectedYear = initialYear ?? calendar.component(.year, from: now)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupToolbar()
        setupPicker()
        selectInitialRows()
    }

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(doneTapped))
        toolbar.items = [cancel, flex, done]
        view.addSubview(toolbar)
    }

    private func setupPicker() {
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.dataSource = self
        picker.delegate = self
        view.addSubview(picker)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            picker.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    private func selectInitialRows() {
        if let monthIndex = months.firstIndex(of: selectedMonth) {
            picker.selectRow(monthIndex, inComponent: 0, animated: false)
        }
        if let yearIndex = years.firstIndex(of: selectedYear) {
            picker.selectRow(yearIndex, inComponent: 1, animated: false)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        onSelect?(selectedMonth, selectedYear)
        dismiss(animated: true)
    }
}

// MARK: - UIPickerViewDataSource, UIPickerViewDelegate

extension CardExpiryPickerViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? months.count : years.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if component == 0 {
            return String(format: "%02d", months[row])
        }
        return String(years[row])
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 {
            selectedMonth = months[row]
        } else {
            selectedYear = years[row]
        }
    }
}
