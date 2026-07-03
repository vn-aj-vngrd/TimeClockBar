# AGENTS.md

## Purpose

Use this file as the starting context for code, docs, tests, reviews, and release work in TimeClockBar.

## Read First

- `README.md` for product scope, setup, and validation commands.
- `docs/ai/architecture.md` for app structure and data flow.
- `docs/ai/development.md` for local workflow and debugging notes.
- `docs/ai/testing.md` for the current testing strategy.
- `docs/ai/release.md` for release checks.
- `docs/ai/coding-standards.md` for Swift and UI conventions.
- `docs/ai/pr-guidelines.md` for review expectations.

## Working Rules

- Understand the relevant SwiftUI, AppKit, WebKit, notification, and defaults flow before editing.
- Make the smallest safe change that preserves the existing menu-bar app shape.
- Reuse existing controller, view, state, and UserDefaults patterns before adding new abstractions.
- Keep UI changes consistent with the current compact popover and native macOS controls.
- Update docs when setup, commands, architecture, release behavior, or user-visible behavior changes.
- Run the smallest relevant Xcode build or test command before finishing, or state exactly why it was not run.

