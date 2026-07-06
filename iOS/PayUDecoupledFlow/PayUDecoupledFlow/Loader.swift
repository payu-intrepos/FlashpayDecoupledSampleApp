//
//  Loader.swift
//  PayUDecoupledFlow
//

import UIKit

final class Loader {

    static let shared = Loader()
    private var overlay: UIView?

    private init() {}

    func show(on viewController: UIViewController) {
        runOnMain { [weak self] in
            self?.showOverlay(on: viewController)
        }
    }

    func hide() {
        runOnMain { [weak self] in
            self?.overlay?.removeFromSuperview()
            self?.overlay = nil
        }
    }

    private func showOverlay(on viewController: UIViewController) {
        overlay?.removeFromSuperview()
        overlay = nil

        guard let hostView = viewController.view.window ?? viewController.view else { return }

        let overlay = UIView(frame: hostView.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        indicator.autoresizingMask = [
            .flexibleLeftMargin, .flexibleRightMargin,
            .flexibleTopMargin, .flexibleBottomMargin
        ]
        indicator.startAnimating()
        overlay.addSubview(indicator)

        hostView.addSubview(overlay)
        self.overlay = overlay
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
