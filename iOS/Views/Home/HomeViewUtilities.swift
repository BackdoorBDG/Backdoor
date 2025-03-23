import UIKit
import os.log

enum FileAppError: Error {
    case fileNotFound(String)
    case fileAlreadyExists(String)
    case invalidFileName(String)
    case invalidFileType(String)
    case permissionDenied(String)
    case directoryCreationFailed(String)
    case fileCreationFailed(String)
    case fileRenameFailed(String, String)
    case fileDeleteFailed(String)
    case fileMoveFailed(String, String)
    case fileUnzipFailed(String, String, Error?)
    case fileZipFailed(String, String, Error?)
    case dylibListingFailed(String, Error?)
    case unknown(Error)
}

struct AlertConfig {
    let title: String?
    let message: String?
    let style: UIAlertController.Style
    let actions: [AlertActionConfig]
    let preferredAction: Int?
    let completionHandler: (() -> Void)?
}

struct AlertActionConfig {
    let title: String?
    let style: UIAlertAction.Style
    let handler: (() -> Void)?
}

class HomeViewUtilities {
    let logger: Logger

    init(logger: Logger = Logger(subsystem: "com.example.FileApp", category: "Utilities")) {
        self.logger = logger
    }

    func handleError(in viewController: UIViewController, error: Error, withTitle title: String) {
        var message: String
        if let fileError = error as? FileAppError {
            switch fileError {
            case .fileNotFound(let fileName):
                message = "File not found: \(fileName). Please check the file name and try again."
                logger.info("File not found: \(fileName)")
            case .fileAlreadyExists(let fileName):
                message = "A file with the name \(fileName) already exists. Please choose a different name."
                logger.info("File already exists: \(fileName)")
            case .unknown(let underlyingError):
                message = "An unknown error occurred: \(underlyingError.localizedDescription)"
                logger.error("Unknown error: \(underlyingError.localizedDescription)")
            default:
                message = error.localizedDescription
            }
        } else {
            message = error.localizedDescription
            logger.error("Unexpected error: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            viewController.present(alert, animated: true, completion: nil)
        }
    }
}

extension UIViewController {
    func presentAlert(config: AlertConfig) {
        let alert = UIAlertController(title: config.title, message: config.message, preferredStyle: config.style)

        if let preferredActionIndex = config.preferredAction, preferredActionIndex < config.actions.count {
            alert.preferredAction = alert.actions[preferredActionIndex]
        }

        for actionConfig in config.actions {
            let action = UIAlertAction(title: actionConfig.title, style: actionConfig.style) { _ in
                actionConfig.handler?()
            }
            alert.addAction(action)
        }

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: config.completionHandler)
        }
    }
}

class HapticFeedbackGenerator {
    static func generateHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    static func generateNotificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    
    static func generateSelectionFeedback() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}