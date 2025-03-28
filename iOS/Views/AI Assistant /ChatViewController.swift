import UIKit

class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView()
    private let inputContainer = UIView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    public var currentSession: ChatSession  // Changed from private to public
    private var messages: [ChatMessage] = []
    
    init(session: ChatSession? = nil) {
        if let session = session {
            self.currentSession = session
        } else {
            let title = "Chat on \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
            do {
                self.currentSession = try CoreDataManager.shared.createChatSession(title: title)
            } catch {
                Logger.shared.log(message: "Failed to create chat session: \(error)", type: .error)
                self.currentSession = ChatSession() // Fallback; assumes ChatSession has a default init
            }
        }
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadMessages()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Navigation bar
        navigationItem.title = currentSession.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "clock.arrow.circlepath"), style: .plain, target: self, action: #selector(showHistory))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "plus.bubble"), style: .plain, target: self, action: #selector(newChat))
        
        // Table view
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UserMessageCell.self, forCellReuseIdentifier: "UserCell")
        tableView.register(AIMessageCell.self, forCellReuseIdentifier: "AICell")
        tableView.register(SystemMessageCell.self, forCellReuseIdentifier: "SystemCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundColor = .systemGray6
        
        // Input container
        inputContainer.backgroundColor = .systemBackground
        inputContainer.layer.shadowColor = UIColor.black.cgColor
        inputContainer.layer.shadowOpacity = 0.1
        inputContainer.layer.shadowOffset = CGSize(width: 0, height: -2)
        inputContainer.layer.shadowRadius = 4
        
        textField.placeholder = "Ask me anything..."
        textField.borderStyle = .roundedRect
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        textField.leftViewMode = .always
        textField.returnKeyType = .send
        textField.delegate = self
        
        sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        
        activityIndicator.color = .systemGray
        activityIndicator.hidesWhenStopped = true
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(inputContainer)
        inputContainer.addSubview(textField)
        inputContainer.addSubview(sendButton)
        inputContainer.addSubview(activityIndicator)
        
        // Constraints
        tableView.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),
            
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 60),
            
            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textField.heightAnchor.constraint(equalToConstant: 40),
            
            sendButton.trailingAnchor.constraint(equalTo: activityIndicator.leadingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            
            activityIndicator.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -8),
            activityIndicator.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor)
        ])
        
        // Keyboard handling
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let keyboardHeight = keyboardFrame.height
            UIView.animate(withDuration: 0.3) {
                self.inputContainer.transform = CGAffineTransform(translationX: 0, y: -keyboardHeight)
                self.tableView.contentInset.bottom = keyboardHeight + 60
                self.scrollToBottom()
            }
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        UIView.animate(withDuration: 0.3) {
            self.inputContainer.transform = .identity
            self.tableView.contentInset.bottom = 0
            self.scrollToBottom()
        }
    }
    
    private func loadMessages() {
        messages = CoreDataManager.shared.getMessages(for: currentSession)
        tableView.reloadData()
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        if !messages.isEmpty {
            let indexPath = IndexPath(row: messages.count - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }
    
    @objc private func showHistory() {
        let historyVC = ChatHistoryViewController()
        historyVC.didSelectSession = { [weak self] session in
            self?.loadSession(session)
        }
        let navController = UINavigationController(rootViewController: historyVC)
        present(navController, animated: true)
    }
    
    @objc private func newChat() {
        let title = "Chat on \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
        do {
            currentSession = try CoreDataManager.shared.createChatSession(title: title)
            messages = []
            tableView.reloadData()
            navigationItem.title = currentSession.title
        } catch {
            Logger.shared.log(message: "Failed to create new chat session: \(error)", type: .error)
        }
    }
    
    func loadSession(_ session: ChatSession) {
        currentSession = session
        loadMessages()
        navigationItem.title = session.title
    }
    
    @objc private func sendMessage() {
        guard let text = textField.text, !text.isEmpty else { return }
        textField.text = ""
        
        do {
            let userMessage = try CoreDataManager.shared.addMessage(to: currentSession, sender: "user", content: text)
            messages.append(userMessage)
            tableView.reloadData()
            scrollToBottom()
            
            activityIndicator.startAnimating()
            sendButton.isEnabled = false
            
            let context = AppContextManager.shared.currentContext()
            let apiMessages = messages.map { OpenAIService.ChatMessage(role: $0.sender == "user" ? "user" : "assistant", content: $0.content ?? "") }
            
            OpenAIService.shared.getAIResponse(messages: apiMessages, context: context) { [weak self] result in
                DispatchQueue.main.async {
                    self?.activityIndicator.stopAnimating()
                    self?.sendButton.isEnabled = true
                    switch result {
                    case .success(let response):
                        do {
                            let aiMessage = try CoreDataManager.shared.addMessage(to: self!.currentSession, sender: "ai", content: response)
                            self?.messages.append(aiMessage)
                            self?.tableView.reloadData()
                            self?.scrollToBottom()
                            
                            // Execute commands
                            let commands = self?.extractCommands(from: response) ?? []
                            for (command, parameter) in commands {
                                AppContextManager.shared.executeCommand(command, parameter: parameter) { [weak self] commandResult in
                                    guard let self = self else { return }
                                    DispatchQueue.main.async {
                                        let systemMessageContent: String
                                        switch commandResult {
                                        case .successWithResult(let message):
                                            systemMessageContent = message
                                        case .unknownCommand(let cmd):
                                            systemMessageContent = "Unknown command: \(cmd)"
                                        }
                                        do {
                                            let systemMessage = try CoreDataManager.shared.addMessage(to: self.currentSession, sender: "system", content: systemMessageContent)
                                            self.messages.append(systemMessage)
                                            self.tableView.reloadData()
                                            self.scrollToBottom()
                                        } catch {
                                            Logger.shared.log(message: "Failed to add system message: \(error)", type: .error)
                                        }
                                    }
                                }
                            }
                        } catch {
                            Logger.shared.log(message: "Failed to add AI message: \(error)", type: .error)
                        }
                    case .failure(let error):
                        do {
                            let errorMessage = try CoreDataManager.shared.addMessage(to: self!.currentSession, sender: "system", content: "Error: \(error.localizedDescription)")
                            self?.messages.append(errorMessage)
                            self?.tableView.reloadData()
                            self?.scrollToBottom()
                        } catch {
                            Logger.shared.log(message: "Failed to add error message: \(error)", type: .error)
                        }
                    }
                }
            }
        } catch {
            Logger.shared.log(message: "Failed to add user message: \(error)", type: .error)
        }
    }
    
    private func extractCommands(from text: String) -> [(command: String, parameter: String)] {
        let pattern = "\\[([^:]+):([^\\]]+)\\]"
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            return matches.compactMap { match in
                if let commandRange = Range(match.range(at: 1), in: text),
                   let paramRange = Range(match.range(at: 2), in: text) {
                    return (String(text[commandRange]), String(text[paramRange]))
                }
                return nil
            }
        } catch {
            Logger.shared.log(message: "Failed to create regex for command extraction: \(error)", type: .error)
            return []
        }
    }
    
    // UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        switch message.sender {
        case "user":
            let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserMessageCell
            cell.configure(with: message)
            return cell
        case "ai":
            let cell = tableView.dequeueReusableCell(withIdentifier: "AICell", for: indexPath) as! AIMessageCell
            cell.configure(with: message)
            return cell
        case "system":
            let cell = tableView.dequeueReusableCell(withIdentifier: "SystemCell", for: indexPath) as! SystemMessageCell
            cell.configure(with: message)
            return cell
        default:
            return UITableViewCell()
        }
    }
}

extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendMessage()
        return true
    }
}