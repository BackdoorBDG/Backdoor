import Foundation

/// Service for interacting with OpenAI API
final class OpenAIService {
    static let shared = OpenAIService(apiKey: "sk-proj-P6BYXJlsZ0oAhG1G9TRmQaSzFSdg0CfwMMz6BEXgpmgEieQl2QBNcbKhr8C5o314orxOa_0S7vT3BlbkFJD5cQCpc5d8bK2GvswZNCPRQ8AIqtlujlLiC8Blj72r5_3d6YWlOEq23QyddeMZF[...]")
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession
    
    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    enum ServiceError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case decodingError(Error)
        case noData
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
            case .noData: return "No response data received"
            }
        }
    }
    
    struct ChatMessage {
        let role: String
        let content: String
    }
    
    func getAIResponse(messages: [ChatMessage], context: AppContext, completion: @escaping (Result<String, ServiceError>) -> Void) {
        guard let url = URL(string: baseURL) else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemMessage: [String: String] = [
            "role": "system",
            "content": "You are a helpful assistant in the Feather app. Current app context: \(context.toString()). Available commands: \(AppContextManager.shared.availableCommands().joined(separator: ", ")). When appropriate, include commands in your response using the format [command:parameter]."
        ]
        
        var apiMessages = [systemMessage]
        apiMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
        
        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.decodingError(error)))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            do {
                let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                if let content = result.choices.first?.message.content {
                    completion(.success(content))
                } else {
                    completion(.failure(.noData))
                }
            } catch {
                completion(.failure(.decodingError(error)))
            }
        }
        task.resume()
    }
}

// Using OpenAIResponse from iOS/Common/OpenAIResponse.swift