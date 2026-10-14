//go:build go1.23

package main

import (
	"os"
	"path/filepath"
	"runtime/debug"
	"sync"
)

// coreCrashFile is read by the app on the next launch (lib/common/crash_report.dart,
// sideTraceFiles) and attached to the crash report. The directory is the app's crash report
// directory: <home>/crash.
const coreCrashFile = "core-crash.log"

var crashOutputOnce sync.Once

// initCrashOutput sends the Go runtime's own crash text (an unrecovered panic, a fatal error
// such as concurrent map writes) to a file as well as stderr.
//
// On Android the core lives inside the app process, so a core crash kills the app, and the
// system reports it as crashNative with the description "crash" and nothing else: 13-10 four
// such reports from 0.9.6 arrived without a single frame. Stderr of an Android app goes
// nowhere, so the file is the only place that text survives.
func initCrashOutput(homeDir string) {
	if homeDir == "" {
		return
	}
	crashOutputOnce.Do(func() {
		dir := filepath.Join(homeDir, "crash")
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return
		}
		f, err := os.OpenFile(filepath.Join(dir, coreCrashFile), os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o600)
		if err != nil {
			return
		}
		// SetCrashOutput duplicates the descriptor, so ours can be closed right away.
		_ = debug.SetCrashOutput(f, debug.CrashOptions{})
		_ = f.Close()
	})
}
