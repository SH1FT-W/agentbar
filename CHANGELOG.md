# Changelog

Release notes for each version are on the [GitHub releases page](https://github.com/SH1FT-W/agentbar/releases). Changes not released yet are listed under *Unreleased*.

## Unreleased

## 26.11.2

### Changed
- Much lighter while agents work: timestamps are parsed about a thousand times faster, the stats file is saved every 2 minutes instead of every 20 seconds, the session list is read at most every 2 seconds, the closed Office no longer redraws in the background, and the menu bar icon only redraws when its numbers change.
- Settings: both menu bar options are in the *Menu Bar* section; greyed out usage options say they need *Fetch usage*; *Fetch usage* mentions the keychain prompt; the fixed shortcut says it is fixed.
- A new pairing code asks first, because your other Macs lose the connection until they get it. Copying the code shows a check mark.
- Session rows keep the file name whole when the line is tight; the helper count shrinks to an icon.
- In the Office, waiting name tags stay orange under the pointer, and the tooltip explains the orange battery (context almost full).
- *Try Again* after a failed update installs again instead of only checking.

### Fixed
- With ~/.claude shared between Macs, a Mac could drop the tokens of its own sessions from the stats when the other Mac reported them too. Sessions whose process runs on this Mac now always count here.
- Writing ~/.claude/settings.json (hooks) never leaves the file readable by other users, not even for a moment, and a change Claude Code makes at the same time is no longer overwritten.
- Other Macs: idle connections from the local network can no longer block the sync, and recorded messages are not accepted again after a Mac went quiet.
- Release notes in the menu and in Settings no longer show raw Markdown.
- German texts: "Sek." used consistently, "Edits OK"; VoiceOver reads the Office shortcut in German.

## 26.11.1

### Added
- "Agent is waiting" notifications wait for a delay you choose (20 seconds by default, or immediately; permission prompts after 10 seconds at most, since the agent is blocked) and notify only once per waiting state, so short pauses and status flicker stay quiet.
- Clicking a notification brings the exact tab to the front in Terminal and iTerm2 (matched by tty) and in Ghostty (matched by folder, only when exactly one tab is there).
- The terminal of a session is now also found without hooks, from the Claude process (tty and app).
- Usage warnings at two thresholds (80 % and 95 % by default) for both the 5-hour and the weekly window, once per threshold and window, remembered across restarts.

### Changed
- No notification while the session's terminal app is in front (unless "Even when in front" is on); a new notification for a session replaces its previous one.
- Keep awake no longer polls every 5 seconds; only "While agents work" follows the agents.
