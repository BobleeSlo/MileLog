# MileLog build report

**Date:** 22 October 2026
**Scope:** the work done in this conversation, from finishing the tracking fixes (19 October) through building the free and paid versions (21–22 October).

## In one paragraph

MileLog went from a personal tracking app with known sync bugs to a version that has a business model built in and can go to TestFlight once the remaining App Store Connect steps are done.

The first phase repaired tracking, cloud sync, receipts and sign-up, added Slovenian, and was merged as PR 1. The second phase built the Free and Paid versions from a reviewed plan:
- **Server side:** subscriptions verified on the server, a monthly allowance of automatic trips, paywall gates, a month-end check, month-aware locking and account deletion.
- **Compliance:** the privacy manifest, the legal drafts and a developer test switch.

All the database changes are live and verified, and the three Edge Functions are deployed. The purchase path is tested against synthetic Apple data, but has not yet handled a real Apple purchase. Apple's In-App Purchase key, the App Store Connect setup and one sandbox purchase are what stand between this branch and a beta.

## What was delivered

### Phase 1: tracking, sync and UX fixes (merged, PR 1)

| Area | Result |
|---|---|
| Trip detection | Trips end on time (GPS jitter filter, stale-fix guard, speed sanity check), and the vehicle falls back to the car picked on the Record screen |
| Cloud sync | Fixed HTTP 400 errors: four columns were missing in the database, which a migration added, and receipt paths were the wrong case for the access rules |
| Sign-up | Confirmation-link redirect fixed, with resend and an "already registered" message |
| Language | In-app language picker (English, Slovenian), formatting follows the chosen language |
| UX test | A critical-user test in the simulator, with its findings fixed |
| Delivery | Installed on the iPhone, build 1.1 (14) |

### Phase 2: free and paid versions (PR 2, open)

Planned with ce-brainstorm and ce-plan, reviewed with ce-doc-review, built with ce-work. All 13 units are done.

| Unit | Delivered |
|---|---|
| U13 | Snapshot of the live schema in the repo (it had never been version-controlled) |
| U1 | Every trip records whether it started automatically or manually; 853 automatic and 7 manual backfilled live |
| U2 | Tables for entitlements, config (allowance 15), usage counters and closed months, all with row-level security |
| U3 | `verify-purchase` and `apple-notifications`, which check Apple's signed data against the pinned Apple root |
| U4 | StoreKit 2 subscription store and a plan resolver that works offline for up to 7 days |
| U5 | Paywall (€3.99 a month, €29.99 a year, 14-day trial), Plan section in Settings, links to the privacy policy and terms |
| U6 | Free plan: 15 automatic trips a month with warnings at 12, 14 and 15; it pauses and resumes on the 1st; manual recording is never blocked |
| U7 | PDF reports, receipts, the month-end check and extra vehicles are Paid; after a lapse, one vehicle keeps recording |
| U8 | Month-end check: unreviewed trips, missing customer and purpose, likely split trips, missing addresses |
| U9 | Month-aware locking synced between devices, a reminder at 18:00 on the last day of the month, notification taps open the right screen |
| U10 | Account deletion in the app, with a server function; the password must have been entered within the last 10 minutes |
| U11 | Privacy manifest, drafts of the privacy policy and terms, App Store privacy answers, App Review notes |
| U12 | Script for beta grants and anonymous usage figures that are sent only with consent and kept separate per account |

Added afterwards, at your request:
- A **permanent Paid grant** for your account (rlipic1@gmail.com).
- A **developer plan switch** in debug and TestFlight builds only, with five options: Real, Free, Paid, Lapsed, and subscription on another account.

**Size:** 21 commits, 63 files changed, about 6,700 lines added. All new text is translated into Slovenian.

## How we know it works

| Check | Result |
|---|---|
| App unit tests | 53 tests, all passing; the suite was re-run after every unit |
| Edge Function tests | 41 tests passing under Node: signature checks, every purchase scenario, grace period, error paths, the order of account deletion |
| Simplify pass | 3 reviewers; 14 duplicate or inefficient code paths cleaned up |
| Code review | 9 lenses (correctness, security, adversarial, testing, maintainability, data migration, reliability, Swift/iOS, deployment); 6 findings confirmed and fixed, 1 rejected after checking |
| Codex review on GitHub | 4 findings, all fixed, replied to and resolved |
| Live database | 5 migrations applied, each verified with checks that ran and then rolled back: backfill counts, the source can't be changed, locks only tighten, a locked trip still accepts purpose edits, row-level security works as you |
| Edge Functions (deployed 22 Oct) | `verify-purchase`, `apple-notifications` and `delete-account` are live; 7 requests checked each function's guards: wrong method, malformed or fake Apple data, no session, signed out |
| Simulator | Settings, the Developer switch and the paywall checked by hand |

### Bugs caught before they reached you

- **Audit log never stored anything.** The audit log in the cloud had silently refused every entry since the start (the policy allowed reading only). It is fixed and now stores entries.
- **Paid plan lost at launch.** A cold launch would have wiped your cached Paid plan before the session was restored. Two reviewers found this independently.
- **Two devices could reopen a closed month.** A second device could have unlocked a closed month by uploading an old copy. The app now fixes the order, and the database blocks it too.
- **Usage consent shared between accounts.** One account's consent would have applied to another account on the same phone.
- **Paywall wouldn't close.** Apple's close button on the paywall did nothing. Found in the simulator.

## What went less well

| Issue | Effect | Lesson |
|---|---|---|
| Missing build tools: no Supabase CLI, Deno or Postgres locally | Edge Functions were tested with Node instead of Deno; migrations could only be tested on the live database | Install the Supabase CLI and Deno, or use a Supabase branch database for testing |
| The live project names migrations by the time they were applied | Repo files had to be renamed twice to match | Apply through the Supabase CLI (`db push`) so the names always match |
| No CI on GitHub | Reviews run, but nothing builds or tests the branch automatically | Add a small GitHub Actions workflow (build plus tests) |
| Simulator taps landed in the wrong place during testing | One tap opened an Apple sign-in prompt (cancelled, nothing entered) | Drive the app by accessibility label rather than coordinates |
| A few simulator test runs failed to launch | Re-runs were needed | Known simulator flakiness; not a code problem |

## Scorecard

| Goal | Status |
|---|---|
| Reliable tracking and sync | ✅ Done and merged |
| Slovenian language | ✅ Done |
| Free and paid versions in the app | ✅ Built and tested, awaiting merge |
| Database ready for the new version | ✅ Live and verified |
| Purchase verification on the server | 🟡 Deployed; waits for the Apple In-App Purchase key (function secrets) |
| A real Apple purchase completed end to end | ❌ Not yet possible: App Store Connect setup is needed |
| Legal pages published | 🟡 Drafted, with your details still to fill in |
| Ready for App Store submission | ❌ Next phase |

## Next steps

### 1. Before the TestFlight beta (owner steps, about 1–2 days)

1. **App Store Connect:**
   - Sign the Paid Apps agreement and add bank and tax details.
   - Enrol in the Small Business Program, so Apple takes 15% instead of 30%.
   - Complete EU trader status.
2. **Create the subscription:**
   - A group with `BT1.MileLog.paid.monthly` (€3.99) and `BT1.MileLog.paid.yearly` (€29.99).
   - A 14-day free trial, the grace period on, Family Sharing off.
3. **In-App Purchase key:** create one for the App Store Server API and set it as function secrets in the Supabase dashboard (Edge Functions › Secrets: `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_PRIVATE_KEY`). Never paste it into chat. Until it's set, `verify-purchase` answers with an error at the status lookup, and the app falls back to the purchase on the device.
4. ~~Deploy the three Edge Functions~~ ✅ Done on 22 October: `verify-purchase` and `delete-account` with the session check, `apple-notifications` without it (Apple sends no session).
5. **Server notification URLs:** point App Store Server Notifications V2 (production and sandbox) at `https://rjkohvddlenyeywhxulc.supabase.co/functions/v1/apple-notifications`.
6. **Legal pages:**
   - Fill the TODOs in `docs/legal/` (name, address, contact email, date).
   - Publish both pages at the addresses in `MileLog/AppLinks.swift`, for example with GitHub Pages.
7. **Merge PR 2** into `main`, bump the build number and upload to TestFlight.

### 2. Prove the purchase path (first TestFlight day)

8. **Make a sandbox purchase** with a sandbox tester account. Check that a row appears in `entitlements` within seconds. This confirms the pinned Apple root certificate, which is the one unproven assumption.
9. **Speed up a renewal and an expiry** in the sandbox, and check that the webhook updates the row.
10. **Delete a throwaway account** from the app, and check that nothing of it is left in Supabase.

### 3. Beta (at least one full calendar month)

11. **Invite testers:** 10–20 people, granted with `tools/grant_entitlement.py` (dry run first).
12. **Use the developer switch** to test the Free experience on your own phone.
13. **Collect feedback** on the allowance size, the month-end check and the paywall wording. Read the usage figures once a month has ended.

### 4. App Store submission

14. **Grant the free year:** give testers their 365-day rows first.
15. **Prepare the App Review material:**
    - A demo account and a demo video of a recorded drive.
    - Fill in `docs/app-store/review-notes.md`.
    - Enter the privacy answers from `docs/app-store/privacy-answers.md`.
16. **Submit** the app version together with the first subscription.

### 5. Decisions still open (from the plan)

- **Trips locked under the old 7-day rule:** keep them as information only, or unlock them while their month is open?
- **Month-end check rule:** flag a business trip missing a customer *or* a purpose, or only one missing both? It currently flags only both missing.
- **Paywall wording for "subscription on another account":** show a masked email, or a generic message? It is currently generic.

### 6. Technical follow-ups (small)

- **Tests in CI:** add a GitHub Actions workflow that builds and runs both test suites.
- **Local tooling:** install the Supabase CLI and Deno.
- **Trip-source trigger:** set its search path (advisor warning).
- **Old `rls_auto_enable` function:** stop signed-out users from calling it (advisor warning, existed before this work).
- **Leaked-password protection:** turn it on in Supabase Auth.
- **Purchase retry:** retry `verify-purchase` when it fails at purchase time, instead of relying on Apple's notification.
- **Per-account usage counting:** usage counts submissions, not accounts. Decide whether that matters before reading the figures.

### Later (ideas from the brainstorm)

- More languages after launch (German, Croatian, Italian).
- A desktop or web view for reports.
- Company or fleet plans, if business users ask for them.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
