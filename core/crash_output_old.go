//go:build !go1.23

package main

// debug.SetCrashOutput appeared in Go 1.23; release builds use a newer toolchain (CI), and an
// older one simply builds a core without the crash file (crash_output.go).
func initCrashOutput(string) {}
