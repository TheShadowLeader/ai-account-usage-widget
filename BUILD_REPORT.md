# Build Report

## Outcome

- App: `AIUsageWidget.app`
- Source: Swift Package in this directory
- Platform: macOS 26.5.2, arm64
- Swift: 6.3.3, source compatibility mode Swift 5
- App version: 1.4.2
- Restored the original detailed provider-card interface and removed the five-layout redesign.
- Added four optional 320×176 compact layouts and native System, Light, and Dark modes.
- Fixed Original clipping, made Codex fill the shared compact frame, restored the animated Claude mascot, and removed the legacy editable Claude working-folder field.
- Replaced the standalone window with an anchored native popover, frosted HUD background, detachable floating panel, and detached-window always-on-top behavior.
- Fixed compact popover surfaces and added shared refresh/settings controls to every compact appearance.

## Provider evidence

### Codex

- Source: official `codex app-server --stdio`, `account/rateLimits/read`.
- Installed client: Codex CLI 0.144.1, authenticated with ChatGPT.
- Latest verified result during build: Plus, weekly window, 9% used.
- The call reads account rate limits and creates no thread or turn.

### Claude

- Source: official Claude Code interactive `/usage` rendered with screen-reader output through `/usr/bin/script` PTY.
- Installed client: Claude Code 2.1.209, authenticated with claude.ai Pro.
- Latest verified result during build: current window 0%, weekly all models 0%, weekly Fable 0%.
- The source reported zero input/output tokens and $0 session cost for the usage-only invocation.
- The app continuously drains bounded output, waits for CLI readiness, sends only `/usage`, and terminates the child after capture.

## Checks

- Release build: PASS (`swift build -c release`)
- Parser self-check: PASS (Codex structured response; Claude three-window output; malformed Claude output rejection)
- Live provider check: PASS for both providers
- Finder/LaunchServices run: PASS; both provider snapshots refreshed in the normalized cache
- Child cleanup: PASS; no Claude/script child remained after refresh
- Normalized cache: `~/Library/Application Support/AIUsageWidget/usage.json`
- Secrets/raw responses stored: none
- Third-party dependencies: none

## Retained improvements

- Optional Claude and Codex percentages in the macOS menu bar
- Custom modern VU-meter app icon in PNG and ICNS formats
- Public-release documentation, MIT license, security policy, and contribution guide
- Providers that are not installed are omitted from the entire app
- Cache clearing no longer clears live in-memory values or triggers a refresh
- Refresh activity indicator caps at eight seconds while slow Claude startup continues safely in the background
- Final VU-meter icon with a compact needle and full rounded-square inset

## Distribution

- App Sandbox: disabled because the app must invoke the user's installed authenticated CLIs.
- Signing: local ad-hoc signature.
- Notarization: not performed; Apple Developer ID credentials are unavailable.
- Full Xcode project: not generated because only Command Line Tools are installed. The native SwiftUI app builds with Swift Package Manager.

## Known limitations

- Claude Code startup from LaunchServices can take up to 45 seconds before `/usage` becomes ready; the UI retains cached data during that interval.
- Claude reset text is displayed as supplied by Claude Code because its screen-reader usage output is human-readable rather than structured JSON.
- Visual accessibility-tree capture from the automation harness timed out. Live adapter completion was verified from the app's normalized cache, process state, and direct live checks.
