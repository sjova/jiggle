#!/usr/bin/env swift
import CoreGraphics
import AppKit
import IOKit.pwr_mgt

let args = CommandLine.arguments
let helpHint = "Run \"jiggle -h\" for help."

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
}

if args.contains("-h") || args.contains("--help") {
    print("""
    Usage: jiggle [interval] [inactivity] [stop_after]

    Keeps the Mac awake and moves the cursor when there is no input.

      interval     Seconds between checks. Default: 60.
      inactivity   Seconds without input before the cursor moves. Default: 60.
      stop_after   Seconds without input before jiggle exits. Default: never.
    """)
    exit(0)
}

if args.count > 4 { fail("too many arguments.\n\(helpHint)") }

func parseArg(_ index: Int, name: String, in args: [String]) -> TimeInterval? {
    guard args.count > index else { return nil }
    guard let value = TimeInterval(args[index]), value.isFinite, value > 0 else {
        fail("\"\(args[index])\" is not a valid value for \(name). Use a positive number of seconds.\n\(helpHint)")
    }
    return value
}

let jiggleInterval  = parseArg(1, name: "interval", in: args) ?? 60
let inactivityStart = parseArg(2, name: "inactivity", in: args) ?? 60
let stopAfter       = parseArg(3, name: "stop_after", in: args)

if let stop = stopAfter, stop <= inactivityStart {
    fail(String(format: "stop_after (%g) must be greater than inactivity (%g).", stop, inactivityStart))
}

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    fail("""
    jiggle needs Accessibility permission to move the cursor.
    Turn it on for the app that started jiggle in System Settings > Privacy & Security > Accessibility. Then run jiggle again.
    """)
}

let jiggleDelta: CGFloat = 16

guard let src = CGEventSource(stateID: .hidSystemState) else {
    fail("could not set up mouse events.")
}

for type in [kIOPMAssertPreventUserIdleSystemSleep, kIOPMAssertPreventUserIdleDisplaySleep] {
    var id: IOPMAssertionID = 0
    guard IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                      "jiggle" as CFString, &id) == kIOReturnSuccess
    else { fail("could not keep the Mac awake.") }
}

// Excludes .mouseMoved: the synthetic jiggle events reset that counter too.
let activityTypes: [CGEventType] = [.keyDown, .flagsChanged, .scrollWheel,
                                    .leftMouseDown, .rightMouseDown, .otherMouseDown]

func secondsSinceInput() -> TimeInterval {
    activityTypes.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min()!
}

var direction: CGFloat = 1
var lastPos = NSEvent.mouseLocation
var lastUserActivity = Date()

while true {
    Thread.sleep(forTimeInterval: jiggleInterval)

    let bounds = CGDisplayBounds(CGMainDisplayID())
    guard bounds.height > 0 else { continue }

    let currentPos = NSEvent.mouseLocation
    let now = Date()

    lastUserActivity = max(lastUserActivity, now.addingTimeInterval(-secondsSinceInput()))

    if currentPos != lastPos {
        lastPos = currentPos
        lastUserActivity = now
        continue
    }

    let idleDuration = now.timeIntervalSince(lastUserActivity)

    if let stop = stopAfter, idleDuration >= stop { exit(0) }
    if idleDuration < inactivityStart { continue }

    let dx = jiggleDelta * direction
    direction = -direction

    let newX = currentPos.x + dx
    let pos  = CGPoint(x: newX, y: bounds.height - currentPos.y)
    lastPos  = CGPoint(x: newX, y: currentPos.y)

    guard let ev = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                           mouseCursorPosition: pos, mouseButton: .left)
    else { continue }

    ev.post(tap: .cghidEventTap)
}
