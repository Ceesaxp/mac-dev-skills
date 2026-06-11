# Deprecated — these tools have moved

The native tools in this directory — **`appkit-api`** and **`appkit-search`** — have moved to the **`apple-platform-tools`** monorepo at `~/Developer/Projects/apple-platform-tools`, where they are named **`sdk-api`** and **`sdk-search`** respectively (same behavior, same flags).

Build and install the canonical tools from the monorepo:

```bash
# in ~/Developer/Projects/apple-platform-tools
mise run install
```

This installs `sdk-api` and `sdk-search` into `~/.local/bin`.

## What stays here

The `appkit-api/` and `appkit-search/` directories alongside this file are the **original sources**, retained for history. They are unchanged. The `scripts/build-tools.sh` script still builds them, but it is superseded — new work happens in the monorepo, not here.
