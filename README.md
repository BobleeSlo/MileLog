# MileLog

iPhone app for logging business car trips: automatic or manual recording,
business / commute / private classification, Supabase sync, and PDF reports
including the Slovenian *potni nalog*.

## First-time setup on a Mac

1. Open `MileLog.xcodeproj` in Xcode. The Supabase package resolves on its own
   (first time takes a minute or two).
2. Create `Config/Secrets.xcconfig` with your Supabase URL and publishable key —
   copy `Config/Secrets.xcconfig.example` and fill it in. This file is
   gitignored, so the credentials never reach GitHub.
   Without it the app builds, but stops at launch with *Missing SUPABASE_URL*.
3. Select your iPhone as the run destination, then **Product → Clean Build
   Folder** (⇧⌘K) and **Run** (⌘R).
4. Check **Settings → About** in the app shows the version you just built.
5. In the Supabase dashboard, **Authentication → URL Configuration**, add
   `milelog://**` to **Redirect URLs**. The sign-up confirmation and
   password-reset emails link back into the app through it; without it
   Supabase sends people to the **Site URL** instead (`http://localhost:3000`
   on a new project, a dead page). Setting the Site URL to
   `milelog://auth/confirm` as well catches any email that has no redirect
   of its own.

## Before every build you install

```
python3 tools/bump_version.py
```

The version lives in the project (`MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION`); `Info.plist` reads it from there. The build number
in **Settings → About** then identifies exactly which code produced a given
Detection Log.

## Project layout

- `MileLog/` — all app sources. It is an Xcode synchronized folder: every
  `.swift` file in it is compiled, nothing outside it is. Keep exactly one
  copy of each file, here.
- `Config/` — build configuration. `MileLog.xcconfig` is committed;
  `Secrets.xcconfig` is not.
- `tools/` — `bump_version.py` (version), `doctor.py` (checks what the target
  actually compiles), `check_sources.py` (compares sources against a reference).
