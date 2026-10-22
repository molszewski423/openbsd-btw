# openbsd-btw: agent instructions

Read the global agent instructions first: `~/.claude/CLAUDE.md` (Claude Code) or `~/.codex/AGENTS.md` (Codex),
both linked to `context/global/AGENTS.md` in the private claude-memory repo. They cover conventions, approvals and
the session protocol (branches `<agent>/<topic>`, signed commits with an `Agent:` trailer, handoff notes). This file
adds what is specific to this repository; where it is stricter, it wins.

## What this is

A self-installing OpenBSD 7.9 desktop: captured dotfiles, an Ansible playbook, and an autoinstall ISO. See
`README.md`.

## Rules for this repository

- **Public on Gitea.** No secrets in `ansible/` or the ISO response files.
- Do not start or restart the `openbsd-btw-test` VM without the owner's go.
