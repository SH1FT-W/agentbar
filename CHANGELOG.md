# Changelog

Release notes for each version are on the [GitHub releases page](https://github.com/SH1FT-W/agentbar/releases). This file lists what is not released yet.

## Unreleased

### Added
- "Agent is waiting" notifications wait for a delay you choose (20 seconds by default, or immediately; permission prompts after 10 seconds at most, since the agent is blocked) and notify only once per waiting state, so short pauses and status flicker stay quiet.
- Clicking a notification brings the exact tab to the front in Terminal and iTerm2 (matched by tty) and in Ghostty (matched by folder, only when exactly one tab is there).
- The terminal of a session is now also found without hooks, from the Claude process (tty and app).
- Usage warnings at two thresholds (80 % and 95 % by default) for both the 5-hour and the weekly window, once per threshold and window, remembered across restarts.

### Changed
- No notification while the session's terminal app is in front (unless "Even when in front" is on); a new notification for a session replaces its previous one.
- Keep awake no longer polls every 5 seconds; only "While agents work" follows the agents.
