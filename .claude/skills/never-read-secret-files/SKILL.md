---
name: never-read-secret-files
description: Read BEFORE opening, printing, copying or searching any file that may hold credentials in CRX-Pulse — .env files, env.json, google-services.json, GoogleService-Info.plist, local.properties, key.properties, keystores, .pem/.p12 keys, or any source file holding a WiFi password, API key, anon/service key, token, connection string or private key. Also read before any bulk `cat`, `grep -r`, `find -exec cat` or "read all config" sweep across the repo, before committing or pushing, and before writing any file that might carry a credential into it. Covers the hardware firmware, the Flutter app and the Supabase layer.
---

# Never read secret files

The user asked for this explicitly on 2026-10-18, for the safety of their
system. It applies to every tier of CRX-Pulse.

## The rule

**Do not read, print, echo, copy or store the contents of any
secret-bearing file in this project.** Filenames are fine. Contents are
not.

Reading a secret pulls it into the conversation transcript, into
persisted tool output, and into any scratchpad file — which spreads it
well beyond the one file the user controls. Once that happens it cannot
be undone by deleting anything afterwards.

This holds even when:

- the task would be easier with the value in hand,
- the file is already committed to git,
- the user previously pasted something similar,
- it is "just" a public or publishable key (anon keys included — treat
  the habit as absolute, so there is no judgement call to get wrong).

## Known secret-bearing files in this repo

Names only. Do not open any of them.

| Path | Holds | Git status |
|---|---|---|
| `hardware/crx_pulse_dev/crx_pulse/crx_pulse.ino` | WiFi SSID + password, Supabase anon key (hardcoded near the top) | **tracked and pushed** |
| `mobile/lib/core/supabase_config.dart` | Supabase project URL + anon key | **tracked and pushed** |
| `mobile/android/app/google-services.json` | Firebase client config | **tracked** |
| `mobile/env.json` | app environment values | gitignored |
| `mobile/android/local.properties` | local SDK paths | gitignored |
| `mobile/ios/Flutter/ephemeral/flutter_native_integration.env` | generated build env | generated |
| `mobile/macos/Flutter/ephemeral/flutter_native_integration.env` | generated build env | generated |

Anything matching these shapes is covered too, whether or not it is
listed: `.env`, `.env.*`, `*secret*`, `*credential*`, `*.keystore`,
`*.jks`, `*.pem`, `*.p12`, `key.properties`.

Not secrets, safe to read freely: `supabase/supabase_schema.sql`,
`mobile/pubspec.yaml`, `mobile/.gitignore`, any `*.example` /
`*.template` file.

## Two files need care, not avoidance

`crx_pulse.ino` and `supabase_config.dart` are ordinary source files
that happen to have credentials pasted into them, so work on them is
unavoidable. When editing either:

- Use `Edit` with a narrowly-scoped `old_string` that does not span the
  credential lines.
- Never print the credential block — not in a diff, not in a quoted
  snippet, not in a commit message, not in an explanation.
- `grep` for the *identifier* (`const char* ssid`, `static const String
  anonKey`) rather than dumping the file, and use `Read` with
  `offset`/`limit` to stay away from the top of the file.
- If a full read is genuinely unavoidable, say so and ask first.

## How to work without the values

- **Does a key exist / what is it called?** `grep` for the variable
  *name*, or read the `*.example` file. Never open the real one.
- **Bulk sweeps.** Exclude these paths. Prefer the `Grep` tool with a
  `glob` filter over `cat`-ing directories; never `find -exec cat`.
- **A value is actually required** (e.g. to reproduce a cloud call):
  stop and ask the user to supply or set it. Do not go and read it.
- **Writing files.** Never copy a credential into a memory file, a
  scratchpad file, a test fixture, a log, a README, or a commit. If code
  needs one, reference the config symbol, not the literal.
- **Before committing.** Check that no staged hunk contains a credential
  value.

## Known exposure (already reported, user is handling it)

`crx_pulse.ino` is tracked with no `.gitignore` and pushed to
`github.com/Eorico/CRX-Pulse-Hardware`; `supabase_config.dart` and
`google-services.json` are tracked and pushed to
`github.com/Eorico/Crx-Pulse-App`. The WiFi password is therefore in
those repositories' commit history, and editing the current file does
not remove it from history. The user has chosen to handle this
themselves — do not start rewriting history or moving credentials into a
`secrets.h` unless they ask. Mentioning it once when relevant is fine;
repeating it is not.

---

*This file is duplicated at the repo root and in `supabase/`, `mobile/`
and `frontend/web/` under `.claude/skills/never-read-secret-files/`, so
that a session opened in any of those folders picks it up. Keep the
copies identical — a security rule that has drifted between copies is
worse than one copy.*
