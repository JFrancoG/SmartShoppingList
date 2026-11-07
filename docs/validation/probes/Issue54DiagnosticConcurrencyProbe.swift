// Execute with Xcode RunCodeSnippet in DistributionDiagnosticsViewModel.swift context.
// Uses a local suspended reader; never calls StoreKit or a backend.
actor SuspendedDiagnosticReader {
    private var calls = 0
    private var pending: CheckedContinuation<AppTransactionObservation, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func read() async -> AppTransactionObservation {
        calls += 1
        started?.resume()
        started = nil
        return await withCheckedContinuation {
            pending = $0
        }
    }

    func waitForCall(_ expected: Int) async {
        if calls >= expected {
            return
        }
        await withCheckedContinuation {
            started = $0
        }
    }

    func count() -> Int { calls }

    func complete(_ value: AppTransactionObservation) {
        pending?.resume(returning: value)
        pending = nil
    }
}

let reader = SuspendedDiagnosticReader()
let model = await MainActor.run {
    DistributionDiagnosticsViewModel(version: "probe", build: "probe") {
        await reader.read()
    }
}
await model.checkIfRequested()
let idleDoesNotRead = await reader.count() == 0
await model.requestCheck()
let first = Task {
    await model.checkIfRequested()
}
await reader.waitForCall(1)
await model.requestCheck()
await model.checkIfRequested()
let singleFlight = await reader.count() == 1
let stillBusy = await model.isChecking
first.cancel()
await model.checkIfRequested()
let cancellationKeepsFlight = await reader.count() == 1
await reader.complete(.verified(.production))
await first.value
let cancelled = await model.observation == .cancelled
let clearedEnvironment = await model.environment == nil
let released = await model.isChecking == false
await model.requestCheck()
let retry = Task {
    await model.checkIfRequested()
}
await reader.waitForCall(2)
await reader.complete(.verified(.sandbox))
await retry.value
let retryWorked = await model.observation == .verified(.sandbox)
let calls = await reader.count()
print("idleDoesNotRead=\(idleDoesNotRead)")
print("singleFlight=\(singleFlight), stillBusy=\(stillBusy)")
print("cancellationKeepsFlight=\(cancellationKeepsFlight)")
print("cancelled=\(cancelled), clearedEnvironment=\(clearedEnvironment), released=\(released)")
print("retryWorked=\(retryWorked), readerCalls=\(calls)")
