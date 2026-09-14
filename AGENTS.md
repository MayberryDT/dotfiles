# Public dotfiles repository

This is a curated public mirror of live configuration, not the source of truth.
After finalized Omarchy desktop changes, run `scripts/sync-from-home`, inspect
the entire diff for private data and credentials, and run
`scripts/check-public`. Commit and push safe finalized changes to `main` in the
same task. Never weaken the checks or publish excluded runtime/private data just
to make synchronization pass.
