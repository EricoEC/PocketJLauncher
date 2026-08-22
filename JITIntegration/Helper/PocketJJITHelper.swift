import ExtensionFoundation
import Foundation
import StikJIT
import XPC

private struct PocketJJITMessageHandler: XPCPeerHandler {
    func handleIncomingRequest(_ message: PocketJJITMessage) -> (any Encodable)? {
        let manager = FileManager.default
        // The regular Generic helper owns a writable sandbox container.
        // StikJIT uses it for the pairing file and personalized DDI cache.
        let root = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketJJIT", isDirectory: true)
        let pairingURL = root.appendingPathComponent("pairingFile.plist")
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try message.pairingData.write(to: pairingURL, options: .atomic)
            defer { try? manager.removeItem(at: pairingURL) }

            let paths = DDIPaths.default(in: root)
            try StikJIT.enableJIT(
                targetPID: message.targetPID,
                pairingFile: pairingURL,
                ddiPaths: paths,
                script: .universal,
                progress: { NSLog("[PocketJJIT] %@", $0) })
            return PocketJJITMessage.Response(
                success: true,
                message: "JIT enabled by the built-in PocketJ Helper.")
        } catch {
            return PocketJJITMessage.Response(
                success: false,
                message: error.localizedDescription)
        }
    }
}

@main
struct PocketJJITHelperExtension: AppExtension {
    @AppExtensionPoint.Bind
    var extensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(
            host: "com.Erico.PocketJLauncher",
            name: "PocketJJITHelper")
    }

    var configuration: some AppExtensionConfiguration {
        ConnectionHandler(onSessionRequest: { request in
            request.accept { _ in
                PocketJJITMessageHandler()
            }
        })
    }
}
