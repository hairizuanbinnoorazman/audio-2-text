# audio-2-text

A macOS dictation app that captures audio via a global hotkey and transcribes speech to text, injecting the result directly into the active application.

## Features

- **Global hotkey** (Ctrl+Option+K) to toggle dictation on/off
- **Floating overlay UI** — dark rounded panel at the bottom of the screen with a waveform animation and live transcription text
- **Text injection** — transcribed text is pasted into the currently focused app via the clipboard
- **Accessory app** — runs without a Dock icon, staying out of your way

## Tech Stack

- **Swift** (Swift Package Manager, macOS 13+)
- **macOS frameworks**: AVFoundation, CoreGraphics, AppKit, CoreFoundation
- **AWS Transcribe Streaming** for speech-to-text
- Native `CGEventTap` for global hotkey capture
- Native `NSPanel` overlay with custom `WaveformView`

## Prerequisites

- macOS 13+
- Swift 6.0+
- AWS credentials configured (for Transcribe)
- **Input Monitoring** permission granted to your terminal or the built binary:
  System Settings > Privacy & Security > Input Monitoring
- **Microphone** permission granted to your terminal (see [Microphone / TCC Permissions](#microphone--tcc-permissions) below)

## Build

```sh
swift build
```

## Usage

```sh
source EXPORT.sh && .build/debug/AudioToText
```

1. The app starts listening for the global hotkey.
2. Press **Ctrl+Option+K** to start dictation — a floating overlay appears at the bottom of the screen with an animated waveform.
3. Press **Ctrl+Option+K** again to stop — the transcribed text is pasted into the active application.
4. Press **Ctrl+C** in the terminal to quit.

If the app fails to start the event tap, it will print instructions for granting Input Monitoring permission and exit.

## Project Structure

```
Sources/AudioToText/
  main.swift           — Entry point; permission checks, NSApplication setup
  AudioRecorder.swift  — AVAudioEngine-based microphone capture (mono Int16 PCM)
  AppController.swift  — State machine (idle → starting → recording → transcribing)
  HotkeyManager.swift  — CGEventTap global hotkey (Ctrl+Option+K)
  MicPermission.swift  — TCC microphone permission check/request
  OverlayPanel.swift   — Floating NSPanel overlay with waveform and status
  Transcriber.swift    — AWS Transcribe Streaming client
  TextInjector.swift   — Clipboard-based text injection (pbcopy + Cmd+V)
Package.swift          — SPM manifest
```

## Permissions

### Input Monitoring

This app uses `CGEventTapCreate` to intercept keyboard events globally. macOS requires **Input Monitoring** permission for this to work. If you see the error:

```
Failed to create event tap.
```

Go to **System Settings > Privacy & Security > Input Monitoring** and add your terminal app or the `audio-2-text` binary.

### Microphone / TCC Permissions

This app uses AVAudioEngine to capture microphone audio. macOS controls microphone access through TCC (Transparency, Consent, and Control). The app checks for microphone permission at startup and will request access if it hasn't been granted yet.

**To grant microphone access:**

1. Go to **System Settings > Privacy & Security > Microphone**
2. Enable access for your terminal app (e.g. Terminal, iTerm2, Alacritty)

**Important: You may need to restart your computer** after granting microphone permission. macOS caches TCC permission state, and in some cases the change does not take effect until after a full reboot. If the app fails to start the audio engine even after granting permission, restart your machine and try again.

**Symptoms of a TCC issue:**

- `engine.start()` hangs for ~10 seconds then fails with `kAudioHardwareNotRunningError` (error code 1937010544)
- The app prints "Microphone permission denied" at startup
- Audio capture produces 0 bytes despite the session appearing healthy

**Learnings from debugging TCC:**

- TCC permission state can become stale. Granting microphone access in System Settings does not always take effect immediately — a reboot may be required to clear the cached state.
- The `kAudioHardwareNotRunningError` after a ~10 second timeout is the characteristic symptom of a TCC block on CoreAudio. It affects both AVAudioEngine and AVCaptureSession equally.
- Embedding an `Info.plist` in the binary (via linker flags or `.app` bundle wrapping) does **not** help — TCC permission for CLI apps is tied to the terminal application, not the executable itself.
- Once TCC is properly granting access (confirmed after a restart), AVAudioEngine works reliably in a CLI/SPM executable without any special bundling or code signing.
