package main

/*
#cgo LDFLAGS: -framework CoreGraphics -framework CoreFoundation -framework AppKit
#include <stdlib.h>
#include "eventtap.h"
#include "overlay_ui.h"
*/
import "C"

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"
	"unsafe"
)

type AppState int

const (
	StateIdle AppState = iota
	StateRecording
	StateTranscribing
)

var (
	stateMu      sync.Mutex
	currentState AppState
	recorder     *Recorder
	transcriber  *Transcriber
)

func init() {
	runtime.LockOSThread()
}

//export goHotkeyCallback
func goHotkeyCallback() {
	stateMu.Lock()
	state := currentState
	stateMu.Unlock()

	switch state {
	case StateIdle:
		startRecording()
	case StateRecording:
		stopRecordingAndTranscribe()
	case StateTranscribing:
		fmt.Println("Transcription in progress, please wait...")
	}
}

func startRecording() {
	fmt.Println("Hotkey pressed, starting dictation...")

	// Set state and show overlay immediately on main thread (responsive UX)
	stateMu.Lock()
	currentState = StateRecording
	stateMu.Unlock()
	C.showOverlay()

	// Pre-initialize done channel to avoid nil-channel panic
	// if Stop() is called before Start() finishes
	recorder = &Recorder{done: make(chan struct{}), ready: make(chan struct{})}

	// PortAudio MUST run off the main thread on macOS
	go func() {
		if err := recorder.Start(); err != nil {
			fmt.Println("Recording error:", err)
			handleTranscriptionError(fmt.Sprintf("Mic error: %v", err))
			return
		}
	}()
}

func stopRecordingAndTranscribe() {
	fmt.Println("Hotkey pressed, stopping recording...")

	stateMu.Lock()
	currentState = StateTranscribing
	stateMu.Unlock()

	updateOverlayText("Transcribing...")
	updateOverlayStatus("Transcribing...")
	C.stopWaveform()

	done := make(chan struct{})
	go func() {
		defer close(done)

		audioData, err := recorder.Stop()
		if err != nil {
			fmt.Println("Stop recording error:", err)
			handleTranscriptionError(fmt.Sprintf("Recording error: %v", err))
			return
		}

		if len(audioData) == 0 {
			handleTranscriptionError("No audio captured")
			return
		}

		text, err := transcriber.Transcribe(context.Background(), audioData)
		if err != nil {
			fmt.Println("Transcription error:", err)
			handleTranscriptionError(fmt.Sprintf("Transcription failed: %v", err))
			return
		}

		fmt.Println("Transcription result:", text)
		updateOverlayText(text)
		updateOverlayStatus("Done!")
		time.Sleep(1 * time.Second)
		C.hideOverlay()

		injectText(text)

		stateMu.Lock()
		currentState = StateIdle
		stateMu.Unlock()
	}()

	// Safety timeout: force-hide overlay if transcription hangs
	go func() {
		select {
		case <-done:
			// Completed normally, nothing to do
		case <-time.After(30 * time.Second):
			fmt.Println("Transcription timed out, force-hiding overlay")
			C.hideOverlay()
			stateMu.Lock()
			currentState = StateIdle
			stateMu.Unlock()
		}
	}()
}

func handleTranscriptionError(msg string) {
	updateOverlayText("")
	updateOverlayStatus(msg)
	go func() {
		time.Sleep(3 * time.Second)
		C.hideOverlay()
		stateMu.Lock()
		currentState = StateIdle
		stateMu.Unlock()
	}()
}

func main() {
	fmt.Println("Initializing AWS Transcribe client...")
	var err error
	transcriber, err = NewTranscriber(context.Background())
	if err != nil {
		fmt.Fprintln(os.Stderr, "Failed to initialize transcriber:", err)
		os.Exit(1)
	}
	fmt.Println("AWS Transcribe client ready.")

	fmt.Println("Listening for Ctrl+Option+K... Press the combo to toggle overlay.")
	fmt.Println("Press Ctrl+C to quit.")

	C.initNSApplication()
	C.setupOverlay()

	rc := C.startEventTap()
	if rc != 0 {
		fmt.Fprintln(os.Stderr, "Failed to create event tap.")
		fmt.Fprintln(os.Stderr, "Grant Input Monitoring permission:")
		fmt.Fprintln(os.Stderr, "  System Settings > Privacy & Security > Input Monitoring")
		os.Exit(1)
	}
}

func updateOverlayText(text string) {
	cstr := C.CString(text)
	defer C.free(unsafe.Pointer(cstr))
	C.updateTranscriptionText(cstr)
}

func updateOverlayStatus(text string) {
	cstr := C.CString(text)
	defer C.free(unsafe.Pointer(cstr))
	C.updateStatusLabel(cstr)
}

func injectText(text string) {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	if err := cmd.Run(); err != nil {
		fmt.Println("Failed to copy to clipboard:", err)
		return
	}

	time.Sleep(50 * time.Millisecond)

	C.simulatePaste()
}
