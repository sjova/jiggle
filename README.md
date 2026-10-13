# jiggle

A mouse jiggler for macOS. It keeps the Mac awake and moves the cursor when there is no input.

## Requirements

- macOS with the Swift compiler. To install it, run `xcode-select --install`.
- Accessibility permission for the app you start jiggle from (e.g. Terminal). Turn it on in System Settings > Privacy & Security > Accessibility.

## Build and install

```sh
swiftc -O jiggle.swift -o ~/.local/bin/jiggle
```

Make sure `~/.local/bin` is in your `PATH`.

## Usage

```
jiggle [interval] [inactivity] [stop_after]
```

| Argument | Meaning | Default |
| --- | --- | --- |
| `interval` | Seconds between checks | 60 |
| `inactivity` | Seconds without input before the cursor moves | 60 |
| `stop_after` | Seconds without input before jiggle exits | never |

Examples:

```sh
jiggle              # run with the defaults
jiggle 60 60 3600   # exit after one hour without input
```

Press Ctrl+C to stop.

## Run in the background

Add to `~/.zshrc`:

```zsh
# Keep the Mac awake and move the cursor when idle
alias stayon='(jiggle &)'
alias stayoff='pkill jiggle'
```

## How it works

- While jiggle runs, the Mac and the display do not go to sleep.
- After `inactivity` seconds without input, jiggle moves the cursor 16 px left and right.
- Typing, scrolling, and clicks count as input, so the cursor does not move while you type.
