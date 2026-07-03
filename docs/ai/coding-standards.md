# Coding Standards

- Follow the existing Swift style: focused types, private helpers, static constants for defaults keys, and explicit ownership.
- Keep UI native to macOS. Prefer SwiftUI/AppKit controls and system symbols before custom drawing.
- Keep state changes inside `TimeclockController` when they affect persisted preferences, timers, reminders, WebKit state, or menu-bar titles.
- Keep lifecycle and system-service wiring inside `AppDelegate`.
- Avoid new abstractions for one caller or one implementation.
- Avoid new dependencies unless Apple frameworks are insufficient.
- Handle system-service failures intentionally, especially notifications, launch at login, hotkeys, and network-driven polling.
- Keep user-visible text short enough for the compact popover and menu bar.

