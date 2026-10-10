// A stand-in for Quickshell's own, whose plugin lives inside the qs binary
// and cannot be loaded by qmltestrunner: a Rectangle that clips its children,
// which is all a test of what is inside one needs.
import QtQuick
Rectangle { clip: true }
