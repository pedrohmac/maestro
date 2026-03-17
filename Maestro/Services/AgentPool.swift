import Foundation
import MaestroCore
import Semaphore

actor AgentPool {
    private var semaphore: AsyncSemaphore
    private(set) var activeRunners: [String: AgentRunner] = [:]  // taskId -> runner
    private var queue: [(taskId: String, taskTitle: String, work: @Sendable () async -> Void)] = []
    private var maxConcurrency: Int

    init(maxConcurrency: Int = 3) {
        self.maxConcurrency = maxConcurrency
        self.semaphore = AsyncSemaphore(value: maxConcurrency)
    }

    func updateMaxConcurrency(_ newMax: Int) {
        // Recreate semaphore only if no active runners
        if activeRunners.isEmpty {
            maxConcurrency = newMax
            semaphore = AsyncSemaphore(value: newMax)
        }
    }

    var activeCount: Int { activeRunners.count }
    var queuedCount: Int { queue.count }

    func getRunner(for taskId: String) -> AgentRunner? {
        activeRunners[taskId]
    }

    func allActiveRunners() -> [AgentRunner] {
        Array(activeRunners.values)
    }

    func submit(taskId: String, taskTitle: String, work: @escaping @Sendable () async -> Void) {
        let runner = AgentRunner(taskId: taskId, taskTitle: taskTitle)
        activeRunners[taskId] = runner

        Task {
            await semaphore.wait()
            await work()
            semaphore.signal()
            activeRunners.removeValue(forKey: taskId)
        }
    }

    func cancel(taskId: String) {
        if let runner = activeRunners[taskId] {
            runner.cancel()
            activeRunners.removeValue(forKey: taskId)
        }
        queue.removeAll { $0.taskId == taskId }
    }

    func cancelAll() {
        for runner in activeRunners.values {
            runner.cancel()
        }
        activeRunners.removeAll()
        queue.removeAll()
    }

    func registerRunner(_ runner: AgentRunner, for taskId: String) {
        activeRunners[taskId] = runner
    }

    func unregisterRunner(for taskId: String) {
        activeRunners.removeValue(forKey: taskId)
    }
}
