---
name: connect-vps-ish
description: Connect an existing VPS from iSH using SSH, diagnose terminal handoffs, and retrieve output for iPhone Back Tap. Use when Steve asks to plug an assistant into his VPS or iSH, connect to his server, fix OCS terminal capture, or copy terminal results into an LLM.
---

# Connect VPS and iSH

Use the existing server and SSH authentication. Preserve Steve's active task.
Load `compress-token-spend` from coden607/skills only if not already loaded.

## Establish available access

1. Identify where commands run: this assistant workspace, iSH locally, or an
   SSH session on the VPS. Never infer connection from a skill being installed.
2. Run `scripts/doctor.sh` on the relevant machine. If no execution connector
   or reachable authenticated SSH exists here, say this chat is not connected.
   Provide one paste-and-run step for iSH/VPS; do not request private keys,
   passwords, bot tokens, or full environment dumps in chat.
3. Prefer the user's existing SSH alias `vps`. Confirm its current resolution
   with `ssh -G vps`; do not reuse an old IP as a verified current address.
4. Use `scripts/link.sh connect [target]` for interactive SSH with a PTY.
   Use `scripts/link.sh check [target]` for a read-only authenticated probe.
   Keep known-host checking enabled; stop on host-key changes.

## Capture and return output

Use coden607/ocs `08-terminal.sh` on the VPS and `~/.local/bin/ocs shell`
from its normal interactive prompt. Retrieve with `scripts/link.sh last [target]`.
On iSH use `scripts/link.sh copy [target]` when `/dev/clipboard` exists as a
character device. The copy operation retrieves output before replacing the
clipboard. Never run clipboard contents as a shell script automatically.

Configure the iPhone shortcut with Run Script over SSH (`~/.local/bin/ocs last`),
Copy to Clipboard (SSH Result), and Open App (selected LLM). Bind it to Back Tap
in iPhone Settings. Give one phone step at a time. Explain that generic actions
leave a manual Paste tap; do not claim arbitrary app input or submission works.

## Resolve the terminal handoff

If tmux reports `can't use /dev/tty`, run `~/.local/bin/ocs shell` directly.
Do not reopen `/dev/tty` for tmux. In an installer, inherit real terminal file
descriptors only when stdin and stdout are TTYs. For piped/noninteractive input,
print the reconnect command. For SSH attachment, request a PTY using `ssh -tt`.
For an unknown TERM, test a supported terminal type rather than guessing a fix.

## Verify and report

Verify authenticated identity/hostname, open the capture session, print a
nonsecret marker, and retrieve it from a second connection. Finally verify the
iPhone clipboard/Back Tap on the actual phone. Label each untested layer
unverified. Tests with fake SSH/tmux are contract tests, not live integration.

Skills contain instructions; they cannot grant this chat remote access.
For direct agent work, use an authenticated execution connector or an assistant
running on the VPS. Avoid opening a public shell endpoint or starting another
paid droplet. Ask Steve before destructive changes or production deployment.
