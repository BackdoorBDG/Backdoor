import CoreData
import UIKit

final class CoreDataManager {
    static let shared = CoreDataManager()
    
    private init() {}
    deinit {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Feather")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        return container
    }()
    
    var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func saveContext() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
    
    /// Clear all objects from fetch request.
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext? = nil) throws {
        let context = context ?? self.context
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        _ = try context.execute(deleteRequest)
    }
    
    func loadImage(from iconUrl: URL?) -> UIImage? {
        guard let iconUrl = iconUrl else { return nil }
        return UIImage(contentsOfFile: iconUrl.path)
    }
    
    // MARK: - Chat Session Management
    
    func createChatSession(title: String) throws -> ChatSession {
        let session = ChatSession(context: context)
        session.sessionID = UUID().uuidString
        session.title = title
        session.creationDate = Date()
        try saveContext()
        return session
    }
    
    func addMessage(to session: ChatSession, sender: String, content: String) throws -> ChatMessage {
        let message = ChatMessage(context: context)
        message.messageID = UUID().uuidString
        message.sender = sender
        message.content = content
        message.timestamp = Date()
        message.session = session
        try saveContext()
        return message
    }
    
    func getMessages(for session: ChatSession) -> [ChatMessage] {
        let request: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        request.predicate = NSPredicate(format: "session == %@", session)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        do {
            return try context.fetch(request)
        } catch {
            Debug.shared.log(message: "CoreDataManager.getMessages: \(error.localizedDescription)", type: .error)
            return []
        }
    }
    
    func getChatSessions() -> [ChatSession] {
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            return try context.fetch(request)
        } catch {
            Debug.shared.log(message: "CoreDataManager.getChatSessions: \(error.localizedDescription)", type: .error)
            return []
        }
    }
    
    func fetchChatHistory(for session: ChatSession) -> [ChatMessage] {
        let request: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        request.predicate = NSPredicate(format: "session == %@", session)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        do {
            let messages = try context.fetch(request)
            Debug.shared.log(message: "Fetched chat history for session: \(session.title ?? "Unnamed") with \(messages.count) messages", type: .info)
            return messages
        } catch {
            Debug.shared.log(message: "CoreDataManager.fetchChatHistory: \(error.localizedDescription)", type: .error)
            return []
        }
    }
    
    func getDatedCertificate() -> [Certificate] {
        let request: NSFetchRequest<Certificate> = Certificate.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            return try context.fetch(request)
        } catch {
            Debug.shared.log(message: "CoreDataManager.getDatedCertificate: \(error.localizedDescription)", type: .error)
            return []
        }
    }
    
    func getCurrentCertificate() -> Certificate? {
        let certificates = getDatedCertificate()
        let selectedIndex = Preferences.selectedCert ?? 0
        guard selectedIndex >= 0 && selectedIndex < certificates.count else { return nil }
        return certificates[selectedIndex]
    }
    
    func getFilesForDownloadedApps(for app: DownloadedApps, getuuidonly: Bool) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let uuid = app.uuid ?? UUID().uuidString
        return getuuidonly ? documentsDirectory.appendingPathComponent(uuid) : documentsDirectory.appendingPathComponent("files/\(uuid)")
    }
}

extension NSPersistentContainer {
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async rethrows -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}