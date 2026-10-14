//go:build go1.23

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The child half: runs only when the parent test re-executes this binary.
func TestCrashOutputChild(t *testing.T) {
	home := os.Getenv("MGLA_CRASH_CHILD_HOME")
	if home == "" {
		t.Skip("child process only")
	}
	if os.Getenv("MGLA_CRASH_CHILD_WIRE") == "1" {
		initCrashOutput(home)
	}
	go func() { panic("mgla core crash probe") }()
	select {}
}

func runCrashChild(t *testing.T, wire bool) string {
	t.Helper()
	home := t.TempDir()
	cmd := exec.Command(os.Args[0], "-test.run=^TestCrashOutputChild$")
	cmd.Env = append(os.Environ(), "MGLA_CRASH_CHILD_HOME="+home)
	if wire {
		cmd.Env = append(cmd.Env, "MGLA_CRASH_CHILD_WIRE=1")
	}
	if err := cmd.Run(); err == nil {
		t.Fatal("child was expected to crash")
	}
	data, err := os.ReadFile(filepath.Join(home, "crash", coreCrashFile))
	if err != nil {
		return ""
	}
	return string(data)
}

// An unrecovered panic in a goroutine kills the process: its text and stack must land in the
// file the app attaches to the next crash report.
func TestCrashOutputWritesPanicToFile(t *testing.T) {
	got := runCrashChild(t, true)
	if !strings.Contains(got, "panic: mgla core crash probe") {
		t.Fatalf("panic text not in %s: %q", coreCrashFile, got)
	}
	if !strings.Contains(got, "goroutine ") || !strings.Contains(got, "crash_output_test.go") {
		t.Fatalf("no stack in %s: %q", coreCrashFile, got)
	}
}

// Control: without initCrashOutput the same crash leaves no file — the check above is not
// passing on something the runtime does by itself.
func TestCrashOutputAbsentWithoutInit(t *testing.T) {
	if got := runCrashChild(t, false); got != "" {
		t.Fatalf("file written without initCrashOutput: %q", got)
	}
}

func TestCrashOutputIgnoresEmptyHome(t *testing.T) {
	initCrashOutput("") // must not panic or touch the working directory
	if _, err := os.Stat(filepath.Join("crash", coreCrashFile)); err == nil {
		t.Fatal("crash file created relative to the working directory")
	}
}
