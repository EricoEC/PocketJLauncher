import ExtensionFoundation
import Foundation
import XPC

@available(iOS 26.0, *)
private final class PocketJJITSession {
    let process: AppExtensionProcess
    let session: XPCSession

    init(process: AppExtensionProcess, session: XPCSession) {
        self.process = process
        self.session = session
    }

    deinit {
        session.cancel(reason: "PocketJ JIT request finished")
        process.invalidate()
    }
}

@objc(PocketJJITCoordinator)
public final class PocketJJITCoordinator: NSObject {
    private static var activeSession: AnyObject?

    @objc(enableJITWithTargetPID:pairingData:completion:)
    public static func enableJIT(targetPID: Int32, pairingData: Data,
                                 completion: @escaping (Bool, String) -> Void) {
        guard #available(iOS 26.0, *) else {
            completion(false, "Built-in JIT requires iOS 26 or later.")
            return
        }

        Task { @MainActor in
            do {
                let monitor = try await AppExtensionPoint.Monitor(
                    appExtensionPoint: .pocketJJITHelper)
                guard let identity = monitor.identities.first else {
                    throw NSError(domain: "PocketJJIT", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey:
                                    "PocketJ JIT Helper was not found in this installation."])
                }

                let process = try await AppExtensionProcess(configuration: .init(
                    appExtensionIdentity: identity,
                    onInterruption: { activeSession = nil }))
                let xpcSession = try process.makeXPCSession()
                try xpcSession.activate()
                activeSession = PocketJJITSession(process: process, session: xpcSession)
                let request = PocketJJITMessage(targetPID: targetPID,
                                                pairingData: pairingData)
                try xpcSession.send(request) {
                    (result: Result<PocketJJITMessage.Response, any Error>) in
                    activeSession = nil
                    switch result {
                    case .success(let response):
                        DispatchQueue.main.async {
                            completion(response.success, response.message)
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            completion(false, error.localizedDescription)
                        }
                    }
                }
            } catch {
                activeSession = nil
                completion(false, error.localizedDescription)
            }
        }
    }
}
