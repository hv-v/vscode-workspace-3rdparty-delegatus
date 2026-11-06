# `.secrets/` — the Delegatus login key

`token` holds the access key: 32 lowercase hex characters, mode `0600`, in a
directory of mode `0700`. It is git-ignored; only this README is tracked.

- `./delegatus.sh init` creates it once and never overwrites it.
- `./delegatus.sh rotate-key` replaces it and restarts the container; every
  browser session signed in with the old key is then refused.
- `./delegatus.sh url` prints the sign-in link, which carries the key. Treat
  that link like the key itself.

The container receives the file as a compose secret
(`/run/secrets/delegatus_token`) and copies it into its own config volume at
every start; nothing else reads it.
