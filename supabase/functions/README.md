# Edge Functions

| Function | Caller | Session |
|---|---|---|
| `verify-purchase` | the app, after a purchase, restore or transaction update | required |
| `apple-notifications` | App Store Server Notifications V2 | none (`verify_jwt = false`), Apple's signature is the gate |

Logic lives in `_shared/` as plain TypeScript with no Deno globals, so the tests run with Node 24:

```bash
node --test supabase/functions/_shared/*.test.ts
```

(`deno test` runs the same files.)

Secrets (`supabase secrets set …`), never in the app or this repo:

- `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_PRIVATE_KEY` — In-App Purchase key for the App Store Server API
- optional `APPLE_BUNDLE_ID` (default `BT1.MileLog`), `APPLE_PRODUCT_IDS` (default `BT1.MileLog.paid.monthly,BT1.MileLog.paid.yearly`)

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase.

Still to prove with real data: verify a TestFlight sandbox transaction against the pinned
Apple Root CA G3 fingerprint in `_shared/apple-jws.ts` before relying on it.
