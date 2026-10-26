#!/usr/bin/env swift
import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices
import IOKit.pwr_mgt
import IOKit.ps

let args = CommandLine.arguments
let helpHint = "Run \"jiggle -h\" for help."
let minBattery = 20

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
}

if args.contains("-h") || args.contains("--help") {
    print("""
    Usage: jiggle [interval] [inactivity] [stop_after]

    Keeps the Mac awake and moves the cursor when there is no input.
    Exits when the Mac runs on battery and the charge is at \(minBattery)% or lower.

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

func batteryPercent() -> Int? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? == kIOPMBatteryPowerKey,
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
        guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = desc[kIOPSCurrentCapacityKey] as? Int,
              let capacity = desc[kIOPSMaxCapacityKey] as? Int, capacity > 0
        else { continue }
        return current * 100 / capacity
    }
    return nil
}

func exitIfBatteryLow() {
    guard let level = batteryPercent(), level <= minBattery else { return }
    print("Battery is at \(level)%. jiggle stopped.")
    exit(0)
}

exitIfBatteryLow()

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

func cursorPosition() -> CGPoint? {
    let height = CGDisplayBounds(CGMainDisplayID()).height
    guard height > 0 else { return nil }
    let location = NSEvent.mouseLocation
    return CGPoint(x: location.x, y: height - location.y)
}

var direction: CGFloat = 1
var lastPos = cursorPosition()
var lastMove = ContinuousClock.now

while true {
    Thread.sleep(forTimeInterval: jiggleInterval)
    exitIfBatteryLow()

    guard let pos = cursorPosition() else { continue }

    if pos != lastPos {
        lastPos = pos
        lastMove = .now
        continue
    }

    let idleDuration = min(secondsSinceInput(), (ContinuousClock.now - lastMove) / .seconds(1))

    if let stop = stopAfter, idleDuration >= stop { exit(0) }
    if idleDuration < inactivityStart { continue }

    let target = CGPoint(x: pos.x + jiggleDelta * direction, y: pos.y)
    direction = -direction
    lastPos = target

    CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
            mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
}
