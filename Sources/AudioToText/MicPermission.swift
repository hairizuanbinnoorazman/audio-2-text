import AVFoundation
import Foundation

enum MicPermission {
    static func ensureAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            print("Microphone permission: authorized.")
        case .notDetermined:
            print("Requesting microphone permission...")
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            if !granted {
                fputs("Microphone permission denied.\n", stderr)
                fputs("Grant permission in System Settings > Privacy & Security > Microphone, then restart your terminal.\n", stderr)
                exit(1)
            }
            print("Microphone permission: granted.")
        case .denied:
            fputs("Microphone permission denied.\n", stderr)
            fputs("Grant permission in System Settings > Privacy & Security > Microphone, then restart your terminal.\n", stderr)
            exit(1)
        case .restricted:
            fputs("Microphone access is restricted by system policy.\n", stderr)
            fputs("Contact your system administrator to allow microphone access.\n", stderr)
            exit(1)
        @unknown default:
            fputs("Microphone permission denied.\n", stderr)
            exit(1)
        }
    }
}
