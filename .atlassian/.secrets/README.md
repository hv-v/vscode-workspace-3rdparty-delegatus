# `.atlassian/.secrets/` — your login for `sync.sh`

```
.secrets/                       mode 700
├── README.md                   tracked
├── credentials.example         tracked placeholder — copy it, never edit it
├── credentials                 IGNORED — your real login, mode 600
└── certs/                      IGNORED except .gitkeep — optional Jenoptik CA files
```

## Credentials

```bash
cd .atlassian/.secrets
install -m 600 credentials.example credentials
nano credentials            # replace the two placeholder values
```

- Everything after the first `=` is the value; special characters are fine,
  surrounding quotes are optional.
- `sync.sh` refuses to run unless the file is mode 600 (or 400).
- Prefer the keyring? Leave `ATLASSIAN_PASSWORD` out and run
  `.atlassian/sync.sh login` once (needs `sudo apt install libsecret-tools`).
  A password in the file wins over the keyring.

## Certificates (optional)

Drop the Jenoptik root + issuing CA as `*.pem` or `*.crt` into `certs/`. Without
them the public-key pins in `../sources.json` authenticate the servers; with
them `sync.sh` checks the chain *and* the pin.

## What keeps this private

| who | kept out by |
|---|---|
| git | the workspace `.gitignore` tracks only `README.md`, `credentials.example` and `certs/.gitkeep` here |
| the code graph | `../.cbmignore` excludes `.secrets/` from the `.atlassian` index; the workspace-root index honours `.gitignore` |
| the agent | `.claude/settings.json` denies `Read` of `credentials`, and `corp-guard.sh` refuses any `Bash` command naming it |

Not kept out: anything running as you on this machine, and the CBM container,
which mounts the whole workspace read-only (it never indexes this folder, but
could read it). Keep the file at mode 600 and the folder at 700.

Check before every push: `git status --short .atlassian/.secrets` must list
nothing but the placeholders.
