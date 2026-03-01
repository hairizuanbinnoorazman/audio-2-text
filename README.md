# audio-2-text

A macOS dictation app that captures audio via a global hotkey and transcribes speech to text, injecting the result directly into the active application.

## Features

- **Global hotkey** (Ctrl+Option+K) to toggle dictation on/off
- **Floating overlay UI** — dark rounded panel at the bottom of the screen with a waveform animation and live transcription text
- **Text injection** — transcribed text is pasted into the currently focused app via the clipboard
- **Accessory app** — runs without a Dock icon, staying out of your way

## Tech Stack

- **Go** with cgo bridging to C and Objective-C
- **macOS frameworks**: CoreGraphics, CoreFoundation, AppKit
- Native `CGEventTap` for global hotkey capture
- Native `NSPanel` overlay with custom `WaveformView`

## Prerequisites

- macOS
- Go 1.25+
- **Input Monitoring** permission granted to your terminal or the built binary:
  System Settings > Privacy & Security > Input Monitoring

## Build

```sh
go build -o audio-2-text
```

## Usage

```sh
./audio-2-text
```

1. The app starts listening for the global hotkey.
2. Press **Ctrl+Option+K** to start dictation — a floating overlay appears at the bottom of the screen with an animated waveform.
3. Press **Ctrl+Option+K** again to stop — the transcribed text is pasted into the active application.
4. Press **Ctrl+C** in the terminal to quit.

If the app fails to start the event tap, it will print instructions for granting Input Monitoring permission and exit.

## Project Structure

```
main.go         — Go entry point; hotkey callback, text injection via pbcopy + simulated Cmd+V
eventtap.c/h    — C event tap using CGEventTap; listens for Ctrl+Option+K keydown events
overlay_ui.m/h  — Objective-C floating NSPanel overlay with waveform animation and status labels
go.mod          — Go module definition (go 1.25)
```

## Permissions

This app uses `CGEventTapCreate` to intercept keyboard events globally. macOS requires **Input Monitoring** permission for this to work. If you see the error:

```
Failed to create event tap.
```

Go to **System Settings > Privacy & Security > Input Monitoring** and add your terminal app or the `audio-2-text` binary.
