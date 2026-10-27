import Foundation

/// Downloads a file and reports progress from 0 to 1.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private let destination: URL

    private init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func download(_ url: URL, to destination: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let downloader = Downloader(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                downloader.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
