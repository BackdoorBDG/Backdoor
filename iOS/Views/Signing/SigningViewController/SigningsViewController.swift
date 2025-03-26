import UIKit
import CoreData

struct BundleOptions {
    var name: String?
    var bundleId: String?
    var version: String?
    var sourceURL: URL?
}

class SigningsViewController: UIViewController {
    private let tableData: [[String]] = [
        [
            "AppIcon",
            String.localized("APPS_INFORMATION_TITLE_NAME"),
            String.localized("APPS_INFORMATION_TITLE_IDENTIFIER"),
            String.localized("APPS_INFORMATION_TITLE_VERSION"),
        ],
        ["Signing"],
        [
            String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_ADD_TWEAKS"),
            String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_MODIFY_DYLIBS"),
        ],
        [String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_PROPERTIES")],
    ]

    private let sectionTitles: [String] = [
        String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_TITLE_CUSTOMIZATION"),
        String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_TITLE_SIGNING"),
        String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_TITLE_ADVANCED"),
        "",
    ]

    private let application: DownloadedApps
    private weak var appsViewController: LibraryViewController?
    private let signingDataWrapper: SigningDataWrapper
    private var mainOptions: SigningMainDataWrapper
    private var bundle: BundleOptions

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.dataSource = self
        table.delegate = self
        table.showsHorizontalScrollIndicator = false
        table.showsVerticalScrollIndicator = false
        table.contentInset.bottom = 70
        return table
    }()

    private var variableBlurView: UIVariableBlurView?
    private let largeButton = ActivityIndicatorButton()
    private let iconCell = IconImageViewCell()
    var signingCompletionHandler: ((Bool) -> Void)?

    init(signingDataWrapper: SigningDataWrapper, application: DownloadedApps, appsViewController: LibraryViewController) {
        self.signingDataWrapper = signingDataWrapper
        self.application = application
        self.appsViewController = appsViewController
        self.mainOptions = SigningMainDataWrapper(mainOptions: MainSigningOptions())
        self.bundle = BundleOptions(
            name: application.name,
            bundleId: application.bundleidentifier,
            version: application.version,
            sourceURL: application.oSU.flatMap { URL(string: $0) }
        )
        super.init(nibName: nil, bundle: nil)

        if let certificate = CoreDataManager.shared.getCurrentCertificate() {
            mainOptions.mainOptions.certificate = certificate
        }
        mainOptions.mainOptions.uuid = application.uuid

        if signingDataWrapper.signingOptions.ppqCheckProtection,
           mainOptions.mainOptions.certificate?.certData?.pPQCheck == true,
           !signingDataWrapper.signingOptions.dynamicProtection {
            mainOptions.mainOptions.bundleId = "\(bundle.bundleId ?? "").\(Preferences.pPQCheckString)"
        }

        if let currentBundleId = bundle.bundleId,
           let newBundleId = signingDataWrapper.signingOptions.bundleIdConfig[currentBundleId] {
            mainOptions.mainOptions.bundleId = newBundleId
        }

        if let currentName = bundle.name,
           let newName = signingDataWrapper.signingOptions.displayNameConfig[currentName] {
            mainOptions.mainOptions.name = newName
        }

        if signingDataWrapper.signingOptions.dynamicProtection {
            Task { await checkDynamicProtection() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigation()
        setupViews()
        setupToolbar()
        #if !targetEnvironment(simulator)
        certAlert()
        #endif

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        tableView.addGestureRecognizer(swipeLeft)
        tableView.addGestureRecognizer(swipeRight)
        NotificationCenter.default.addObserver(self, selector: #selector(fetch), name: Notification.Name("reloadSigningController"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: Notification.Name("reloadSigningController"), object: nil)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              indexPath.section == 1, indexPath.row == 0 else { return }

        let certificates = CoreDataManager.shared.getDatedCertificate()
        guard certificates.count > 1,
              let currentIndex = certificates.firstIndex(where: { $0 == mainOptions.mainOptions.certificate }) else { return }

        let newIndex = gesture.direction == .left ?
            (currentIndex + 1) % certificates.count :
            (currentIndex - 1 + certificates.count) % certificates.count

        let feedbackGenerator = UISelectionFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.selectionChanged()

        Preferences.selectedCert = newIndex
        mainOptions.mainOptions.certificate = certificates[newIndex]
        tableView.reloadRows(at: [indexPath], with: gesture.direction == .left ? .left : .right)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func setupNavigation() {
        let logoImageView = UIImageView(image: UIImage(named: "feather_glyph"))
        logoImageView.contentMode = .scaleAspectFit
        navigationItem.titleView = logoImageView
        navigationController?.navigationBar.prefersLargeTitles = false
        isModalInPresentation = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String.localized("DISMISS"), style: .done, target: self, action: #selector(closeSheet))
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupToolbar() {
        largeButton.translatesAutoresizingMaskIntoConstraints = false
        largeButton.addTarget(self, action: #selector(startSign), for: .touchUpInside)

        let gradientMask = VariableBlurViewConstants.defaultGradientMask
        variableBlurView = UIVariableBlurView(frame: .zero)
        variableBlurView?.gradientMask = gradientMask
        variableBlurView?.transform = CGAffineTransform(rotationAngle: .pi)
        variableBlurView?.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(variableBlurView!)
        view.addSubview(largeButton)

        let height: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 65 : 80
        NSLayoutConstraint.activate([
            variableBlurView!.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            variableBlurView!.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            variableBlurView!.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            variableBlurView!.heightAnchor.constraint(equalToConstant: height),

            largeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            largeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            largeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -17),
            largeButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        variableBlurView?.layer.zPosition = 3
        largeButton.layer.zPosition = 4
    }

    private func certAlert() {
        guard mainOptions.mainOptions.certificate == nil else { return }
        let alert = UIAlertController(
            title: String.localized("APP_SIGNING_VIEW_CONTROLLER_NO_CERTS_ALERT_TITLE"),
            message: String.localized("APP_SIGNING_VIEW_CONTROLLER_NO_CERTS_ALERT_DESCRIPTION"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String.localized("LAME"), style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true, completion: nil)
    }

    @objc private func closeSheet() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func fetch() {
        tableView.reloadData()
    }

    @objc private func startSign() {
        navigationItem.leftBarButtonItem = nil
        largeButton.showLoadingIndicator()
        signInitialApp(
            bundle: bundle,
            mainOptions: mainOptions,
            signingOptions: signingDataWrapper,
            appPath: CoreDataManager.shared.getFilesForDownloadedApps(for: application, getuuidonly: false)
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let (signedPath, signedApp)):
                self.appsViewController?.fetchSources()
                self.appsViewController?.tableView.reloadData()
                Debug.shared.log(message: signedPath.path)
                if self.signingDataWrapper.signingOptions.installAfterSigned {
                    self.appsViewController?.startInstallProcess(meow: signedApp, filePath: signedPath.path)
                    self.signingCompletionHandler?(true)
                }
            case .failure(let error):
                Debug.shared.log(message: "Signing failed: \(error.localizedDescription)", type: .error)
                self.signingCompletionHandler?(false)
            }
            self.dismiss(animated: true)
        }
    }

    private func checkDynamicProtection() async {
        guard signingDataWrapper.signingOptions.ppqCheckProtection,
              mainOptions.mainOptions.certificate?.certData?.pPQCheck == true,
              let bundleId = bundle.bundleId else { return }

        let shouldModify = await BundleIdChecker.shouldModifyBundleId(originalBundleId: bundleId)
        if shouldModify {
            mainOptions.mainOptions.bundleId = "\(bundleId).\(Preferences.pPQCheckString)"
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
        }
    }
}

extension SigningsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { sectionTitles.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tableData[section].count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sectionTitles[section] }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { sectionTitles[section].isEmpty ? 0 : 40 }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = InsetGroupedSectionHeader(title: sectionTitles[section])
        return headerView
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellText = tableData[indexPath.section][indexPath.row]
        switch cellText {
        case "AppIcon":
            iconCell.configure(with: mainOptions.mainOptions.iconURL ?? getIconURL(for: application))
            iconCell.accessoryType = .disclosureIndicator
            return iconCell

        case String.localized("APPS_INFORMATION_TITLE_NAME"):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = String.localized("APPS_INFORMATION_TITLE_NAME")
            cell.detailTextLabel?.text = mainOptions.mainOptions.name ?? bundle.name
            cell.accessoryType = .disclosureIndicator
            return cell

        case String.localized("APPS_INFORMATION_TITLE_IDENTIFIER"):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = String.localized("APPS_INFORMATION_TITLE_IDENTIFIER")
            cell.detailTextLabel?.text = mainOptions.mainOptions.bundleId ?? bundle.bundleId
            cell.accessoryType = .disclosureIndicator
            return cell

        case String.localized("APPS_INFORMATION_TITLE_VERSION"):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = String.localized("APPS_INFORMATION_TITLE_VERSION")
            cell.detailTextLabel?.text = mainOptions.mainOptions.version ?? bundle.version
            cell.accessoryType = .disclosureIndicator
            return cell

        case "Signing":
            if let certificate = mainOptions.mainOptions.certificate {
                let cell = CertificateViewTableViewCell()
                cell.configure(with: certificate, isSelected: false)
                cell.selectionStyle = .none
                return cell
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = String.localized("SETTINGS_VIEW_CONTROLLER_CELL_CURRENT_CERTIFICATE_NOSELECTED")
                cell.textLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .none
                return cell
            }

        case String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_ADD_TWEAKS"),
             String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_MODIFY_DYLIBS"),
             String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_PROPERTIES"):
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = cellText
            cell.accessoryType = .disclosureIndicator
            return cell

        default:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = cellText
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let itemTapped = tableData[indexPath.section][indexPath.row]
        switch itemTapped {
        case "AppIcon":
            importAppIconFile()

        case String.localized("APPS_INFORMATION_TITLE_NAME"):
            let controller = SigningsInputViewController(
                parentView: self,
                initialValue: mainOptions.mainOptions.name ?? bundle.name ?? "",
                valueToSaveTo: indexPath.row
            )
            navigationController?.pushViewController(controller, animated: true)

        case String.localized("APPS_INFORMATION_TITLE_IDENTIFIER"):
            let controller = SigningsInputViewController(
                parentView: self,
                initialValue: mainOptions.mainOptions.bundleId ?? bundle.bundleId ?? "",
                valueToSaveTo: indexPath.row
            )
            navigationController?.pushViewController(controller, animated: true)

        case String.localized("APPS_INFORMATION_TITLE_VERSION"):
            let controller = SigningsInputViewController(
                parentView: self,
                initialValue: mainOptions.mainOptions.version ?? bundle.version ?? "",
                valueToSaveTo: indexPath.row
            )
            navigationController?.pushViewController(controller, animated: true)

        case String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_ADD_TWEAKS"):
            let controller = SigningsTweakViewController(signingDataWrapper: signingDataWrapper)
            navigationController?.pushViewController(controller, animated: true)

        case String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_MODIFY_DYLIBS"):
            let controller = SigningsDylibViewController(
                mainOptions: mainOptions,
                app: CoreDataManager.shared.getFilesForDownloadedApps(for: application, getuuidonly: false)
            )
            navigationController?.pushViewController(controller, animated: true)

        case String.localized("APP_SIGNING_VIEW_CONTROLLER_CELL_PROPERTIES"):
            let controller = SigningsAdvancedViewController(signingDataWrapper: signingDataWrapper, mainOptions: mainOptions)
            navigationController?.pushViewController(controller, animated: true)

        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension SigningsViewController {
    private func getIconURL(for app: DownloadedApps) -> URL? {
        guard let iconURLString = app.iconURL, let url = URL(string: iconURLString) else { return nil }
        let filesURL = CoreDataManager.shared.getFilesForDownloadedApps(for: app, getuuidonly: false)
        return filesURL.appendingPathComponent(url.lastPathComponent)
    }

    private func importAppIconFile() {
        // Assuming this method exists elsewhere or needs implementation
        // For completeness, a placeholder implementation:
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image])
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }
}

extension SigningsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        mainOptions.mainOptions.iconURL = url
        tableView.reloadData()
    }
}