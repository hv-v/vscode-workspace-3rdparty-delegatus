# `.gitlab/.secrets/`: your GitLab login for `sync.sh`

```
.secrets/                       mode 700
├── README.md                   tracked
├── credentials.example         tracked placeholder; copy it, never edit it
├── credentials                 IGNORED: your real login, mode 600
└── certs/                      IGNORED except .gitkeep: optional Jenoptik CA files
```

## Credentials

```bash
cd .gitlab/.secrets
install -m 600 credentials.example credentials
nano credentials            # replace the placeholder values
```

Two forms, use one:

| keys | what `sync.sh` does with it |
|---|---|
| `GITLAB_USER` + `GITLAB_PASSWORD` | logs in once per run and asks the server for a token limited to `read_api`. It refuses the token if the server grants anything wider, and revokes it on exit. |
| `GITLAB_TOKEN` | a personal access token, if you can ever create one. It is used only if its scopes are all `read_*`. |

- Everything after the first `=` is the value. Special characters are fine,
  and surrounding quotes are optional.
- `sync.sh` refuses to run unless the file is mode 600 (or 400).
- **A refused login stops the script, with no retry.** Repeated failures count
  against your account's lockout.

## Certificates (optional)

Drop the Jenoptik root + issuing CA as `*.pem` or `*.crt` into `certs/`.
Without them, the public-key pin in `../sources.json` authenticates the
server. With them, `sync.sh` checks the chain *and* the pin.

## What keeps this private

| who | kept out by |
|---|---|
| git | the workspace `.gitignore` tracks only `README.md`, `credentials.example` and `certs/.gitkeep` here |
| the code graph | `../.cbmignore` excludes `.secrets/` from the `.gitlab` index |
| the agent | `.claude/settings.json` denies `Read` of `credentials`, and `corp-guard.sh` refuses any `Bash` command naming it |

Not kept out: anything running as you on this machine, and the CBM container,
which mounts the whole workspace read-only. It never indexes this folder, but
could read it. Keep the file at mode 600 and the folder at 700.

Check before every push: `git status --short .gitlab/.secrets` must list
nothing but the placeholders.
