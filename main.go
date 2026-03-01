package main

/*
#cgo LDFLAGS: -framework CoreGraphics -framework CoreFoundation -framework AppKit
#include <stdlib.h>
#include "eventtap.h"
#include "overlay_ui.h"
*/
import "C"

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
	"unsafe"
)

func init() {
	runtime.LockOSThread()
}

//export goHotkeyCallback
func goHotkeyCallback() {
	if C.isOverlayVisible() != 0 {
		fmt.Println("Hotkey pressed, finishing dictation...")
		cstr := C.getTranscriptionText()
		text := C.GoString(cstr)
		C.free(unsafe.Pointer(cstr))
		C.hideOverlay()
		if text != "" {
			go func() {
				injectText(text)
			}()
		}
	} else {
		fmt.Println("Hotkey pressed, starting dictation...")
		C.showOverlay()
	}
}

func main() {
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
