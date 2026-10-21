# App Store Connect: App Privacy answers

These answers match `MileLog/PrivacyInfo.xcprivacy`. Keep both in sync when data collection changes.

**Do you or your third-party partners collect data from this app?** Yes.

**Tracking:** No. MileLog does not link data with third-party data for advertising or share it with data brokers. No tracking domains, no IDFA, no App Tracking Transparency prompt.

## Data types

| Data type (App Store Connect) | Collected | Linked to user | Used for tracking | Purposes | What it is in MileLog |
|---|---|---|---|---|---|
| Location > Precise Location | Yes | Yes | No | App Functionality | Trip start/end coordinates and GPS route points |
| Location > Coarse Location | No | - | - | - | Not collected separately (precise location covers it) |
| Contact Info > Email Address | Yes | Yes | No | App Functionality | Sign-in email |
| Contact Info > Name | Yes | Yes | No | App Functionality | Driver name in the report settings |
| Contact Info > Physical Address | Yes | Yes | No | App Functionality | Home and work address used to recognise commute trips |
| Identifiers > User ID | Yes | Yes | No | App Functionality | Account ID (also Apple appAccountToken on purchases) |
| Identifiers > Device ID | No | - | - | - | Not collected |
| User Content > Photos or Videos | Yes | Yes | No | App Functionality | Receipt photos |
| User Content > Other User Content | Yes | Yes | No | App Functionality | Trip purpose, customer, notes, vehicle name and plate, receipt details |
| Usage Data > Product Interaction | Yes | Yes | No | Analytics, App Functionality | Opt-in monthly count ranges: automatic trips, report generations, receipt saves, month-end check opens |
| Purchases > Purchase History | Yes | Yes | No | App Functionality | Subscription product, status, expiry, Apple transaction ID |
| Financial Info (payment, credit) | No | - | - | - | Apple handles payment; no card data reaches MileLog |
| Diagnostics (crash, performance) | No | - | - | - | No crash reporting SDK; the detection log stays on device unless the user shares it manually |
| Contacts, Health, Fitness, Browsing/Search History, Sensitive Info, Audio, Gameplay, Advertising Data | No | - | - | - | Not collected |

## Notes for the answers

- **Not collected (on-device only):** motion data (CoreMotion), Bluetooth audio route check, Face ID / Touch ID, Vision text recognition, local notifications, the detection log. Apple counts data as "collected" only when it leaves the device in a way the developer can access.
- **Product Interaction is "linked"** because the opt-in usage request is made from a signed-in session, even though the stored counters hold no account ID, device ID or location. Declaring it linked is the conservative answer.
- **Purpose "App Functionality" for Product Interaction:** the figures set the Free plan allowance. If you prefer, Analytics alone is also defensible; keep the manifest identical to whatever you choose.
- **Name, Physical Address and Other User Content** were added beyond the minimum list because the app syncs the driver name, home/work address and free-text trip fields to Supabase. Remove them only if those fields stop leaving the device.
- **Required-reason APIs** (manifest only, not part of this questionnaire): UserDefaults `CA92.1` (no other required-reason API is used). Third-party SDK (supabase-swift) declarations come from its own privacy manifest.
- Privacy Policy URL: https://bobleeslo.github.io/milelog/privacy-policy
