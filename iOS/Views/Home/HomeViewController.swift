import UIKit
import ZIPFoundation

class HomeViewController: UIViewController, UISearchResultsUpdating, UIDocumentPickerDelegate, UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {

    // MARK: - Properties
    private var fileList: [File] = []
    private var filteredFileList: [File] = []
    private let fileManager = FileManager.default
    private let searchController = UISearchController(searchResultsController: nil)
    private var sortOrder: SortOrder = .name
    private let fileHandlers = HomeViewFileHandlers()
    private let utilities = HomeViewUtilities()
    private lazy var tableHandlers = HomeViewTableHandlers(utilities: utilities)

    private var documentsDirectory: URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
        createFilesDirectoryIfNeeded(at: directory)
        return directory
    }

    enum SortOrder: String {
        case name, date, size
    }

    private var activityIndicator: UIActivityIndicatorView {
        return HomeViewUI.activityIndicator
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActivityIndicator()
        loadFiles()
        configureTableView()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        view.layer.applyFuturisticShadow()

        let navItem = UINavigationItem(title: "File Nexus")
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle.fill"), style: .plain, target: self, action: #selector(showMenu))
        let uploadButton = UIBarButtonItem(customView: HomeViewUI.uploadButton)
        let addButton = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: self, action: #selector(addDirectory))

        HomeViewUI.uploadButton.addTarget(self, action: #selector(importFile), for: .touchUpInside)
        HomeViewUI.uploadButton.addGradientBackground()
        navItem.rightBarButtonItems = [menuButton, uploadButton, addButton]
        HomeViewUI.navigationBar.setItems([navItem], animated: false)
        view.addSubview(HomeViewUI.navigationBar)

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Files"
        searchController.searchBar.tintColor = .systemCyan
        navigationItem.searchController = searchController
        definesPresentationContext = true

        view.addSubview(HomeViewUI.fileListTableView)
        NSLayoutConstraint.activate([
            HomeViewUI.navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            HomeViewUI.navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            HomeViewUI.navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            HomeViewUI.fileListTableView.topAnchor.constraint(equalTo: HomeViewUI.navigationBar.bottomAnchor, constant: 10),
            HomeViewUI.fileListTableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            HomeViewUI.fileListTableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            HomeViewUI.fileListTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])

        applyFuturisticTransition()
    }

    private func setupActivityIndicator() {
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureTableView() {
        HomeViewUI.fileListTableView.delegate = self
        HomeViewUI.fileListTableView.dataSource = self
        HomeViewUI.fileListTableView.dragDelegate = self
        HomeViewUI.fileListTableView.dropDelegate = self
        HomeViewUI.fileListTableView.register(FileTableViewCell.self, forCellReuseIdentifier: "FileCell")
        HomeViewUI.fileListTableView.backgroundColor = .clear
        HomeViewUI.fileListTableView.layer.cornerRadius = 15
        HomeViewUI.fileListTableView.layer.applyFuturisticShadow()
    }

    private func createFilesDirectoryIfNeeded(at directory: URL) {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Directory Creation Error")
        }
    }

    private func saveState() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder")
    }

    // MARK: - File Operations
    private func loadFiles() {
        activityIndicator.startAnimating()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let files = try self.fileManager.contentsOfDirectory(at: self.documentsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
                let fileObjects = files.map { File(url: $0) }
                DispatchQueue.main.async {
                    self.fileList = fileObjects
                    self.sortFiles()
                    HomeViewUI.fileListTableView.reloadData()
                    self.activityIndicator.stopAnimating()
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.utilities.handleError(in: self, error: error, withTitle: "File Load Error")
                }
            }
        }
    }

    @objc private func importFile() {
        fileHandlers.uploadFile(viewController: self)
    }

    func handleImportedFile(url: URL) {
        let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                guard url.startAccessingSecurityScopedResource() else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped resource"]) }
                defer { url.stopAccessingSecurityScopedResource() }

                if url.pathExtension.lowercased() == "zip" {
                    try self.fileManager.unzipItem(at: url, to: destinationURL.deletingLastPathComponent())
                } else {
                    try self.fileManager.copyItem(at: url, to: destinationURL)
                }

                DispatchQueue.main.async {
                    self.loadFiles()
                    HapticFeedbackGenerator.generateNotificationFeedback(type: .success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.utilities.handleError(in: self, error: error, withTitle: "File Import Error")
                }
            }
        }
    }

    func deleteFile(at index: Int) {
        let file = searchController.isActive ? filteredFileList[index] : fileList[index]
        do {
            try fileManager.removeItem(at: file.url)
            if searchController.isActive {
                filteredFileList.remove(at: index)
            } else {
                fileList.remove(at: index)
            }
            HomeViewUI.fileListTableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
            HapticFeedbackGenerator.generateNotificationFeedback(type: .success)
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "File Delete Error")
        }
    }

    private func sortFiles() {
        switch sortOrder {
        case .name:
            fileList.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .date:
            fileList.sort { $0.date > $1.date }
        case .size:
            fileList.sort { $0.size > $1.size }
        }
    }

    // MARK: - UI Actions
    @objc private func showMenu() {
        let alertController = UIAlertController(title: "Sort By", message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "Name", style: .default) { [weak self] _ in
            self?.sortOrder = .name
            self?.sortFiles()
            HomeViewUI.fileListTableView.reloadData()
        })
        alertController.addAction(UIAlertAction(title: "Date", style: .default) { [weak self] _ in
            self?.sortOrder = .date
            self?.sortFiles()
            HomeViewUI.fileListTableView.reloadData()
        })
        alertController.addAction(UIAlertAction(title: "Size", style: .default) { [weak self] _ in
            self?.sortOrder = .size
            self?.sortFiles()
            HomeViewUI.fileListTableView.reloadData()
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = alertController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(alertController, animated: true, completion: nil)
    }

    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text?.lowercased(), !searchText.isEmpty else {
            filteredFileList = fileList
            return
        }
        filteredFileList = fileList.filter { $0.name.lowercased().contains(searchText) }
        HomeViewUI.fileListTableView.reloadData()
    }

    @objc private func addDirectory() {
        let alertController = UIAlertController(title: "Add Directory", message: "Enter the name of the new directory", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Directory Name"
            textField.autocapitalizationType = .none
        }

        alertController.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self,
                  let textField = alertController.textFields?.first,
                  let directoryName = textField.text?.trimmingCharacters(in: .whitespaces),
                  !directoryName.isEmpty else { return }

            let newDirectoryURL = self.documentsDirectory.appendingPathComponent(directoryName)
            do {
                try self.fileManager.createDirectory(at: newDirectoryURL, withIntermediateDirectories: false, attributes: nil)
                self.loadFiles()
                HapticFeedbackGenerator.generateNotificationFeedback(type: .success)
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: "Directory Creation Error")
            }
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    private func showFileOptions(for file: File) {
        let alertController = UIAlertController(title: "File Options", message: file.name, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            self?.openFile(file)
        })
        alertController.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self, let index = self.fileList.firstIndex(of: file) else { return }
            self.deleteFile(at: index)
        })
        alertController.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            self?.fileHandlers.shareFile(viewController: self, fileURL: file.url)
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let popover = alertController.popoverPresentationController,
           let cell = HomeViewUI.fileListTableView.cellForRow(at: IndexPath(row: fileList.firstIndex(of: file) ?? 0, section: 0)) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(alertController, animated: true, completion: nil)
    }

    private func openFile(_ file: File) {
        let fileExtension = file.url.pathExtension.lowercased()
        let editor: UIViewController
        switch fileExtension {
        case "txt", "md":
            editor = TextEditorViewController(fileURL: file.url)
        case "plist":
            editor = PlistEditorViewController(fileURL: file.url)
        case "ipa":
            editor = IPAEditorViewController(fileURL: file.url)
        default:
            editor = HexEditorViewController(fileURL: file.url)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchController.isActive ? filteredFileList.count : fileList.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as? FileTableViewCell else {
            return UITableViewCell()
        }
        let file = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        cell.configure(with: file)
        cell.backgroundColor = .clear
        cell.layer.cornerRadius = 10
        return cell
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let file = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        showFileOptions(for: file)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (_, _, completion) in
            guard let self else { return }
            let file = self.searchController.isActive ? self.filteredFileList[indexPath.row] : self.fileList[indexPath.row]
            if let index = self.fileList.firstIndex(of: file) {
                self.deleteFile(at: index)
            }
            completion(true)
        }
        deleteAction.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    // MARK: - UITableViewDragDelegate
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let file = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: file.url.path as NSString))
        session.localContext = file.name
        return [dragItem]
    }

    // MARK: - UITableViewDropDelegate
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        tableHandlers.tableView(tableView, performDropWith: coordinator, fileList: &fileList, documentsDirectory: documentsDirectory, loadFiles: loadFiles)
    }

    // MARK: - UIDocumentPickerDelegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else { return }
        handleImportedFile(url: selectedFileURL)
    }

    // MARK: - Private Methods
    private func applyFuturisticTransition() {
        let transition = CATransition()
        transition.duration = 0.5
        transition.type = .push
        transition.subtype = .fromTop
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer.add(transition, forKey: nil)
    }
}

extension CALayer {
    func applyFuturisticShadow() {
        shadowColor = UIColor.systemCyan.withAlphaComponent(0.3).cgColor
        shadowOffset = CGSize(width: 0, height: 5)
        shadowRadius = 10
        shadowOpacity = 0.8
        masksToBounds = false
    }
}