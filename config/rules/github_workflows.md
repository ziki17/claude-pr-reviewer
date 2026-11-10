Adapted from alibaba/open-code-review `github_workflows.md` (Apache-2.0); reliability and style items removed.

- **`pull_request_target` + checkout of PR head**: runs untrusted code with write token and secrets. Flag when `actions/checkout` uses `github.event.pull_request.head.sha|ref` under `pull_request_target` without isolation.
- **Script injection**: `${{ github.event.* }}` (issue/PR title, body, branch name, comment) interpolated directly into `run:`. Must go through `env:` and be quoted as `"$VAR"`.
- **Secrets exposure**: secrets echoed to logs, written to artifacts, or passed to steps/actions that do not need them.
- **Permissions**: new job or workflow with `permissions: write-all`, or a newly added write scope the job does not use.
- **Unpinned third-party actions**: non-`actions/*` action referenced by a mutable tag or branch instead of a full commit SHA.
- **Hardcoded credentials** in the workflow instead of `secrets.*`.
- **Broken logic**: `needs:` pointing at a non-existent job, `if:` conditions that can never be true (wrong event name, unquoted expression), misspelled action inputs (silently ignored).
