# MileLog Privacy Policy

Last updated: TODO (date of publication)

This policy explains what personal data the MileLog iOS app collects, why, where it is kept and what rights you have. MileLog is made by one developer in Slovenia (EU), so the EU General Data Protection Regulation (GDPR) applies.

## 1. Who is responsible

The controller of your personal data is:

- TODO: full legal name (or business name, e.g. s.p.)
- TODO: postal address, Slovenia
- TODO: contact email for privacy requests

There is no data protection officer; write to the email above with any question or request.

## 2. What MileLog collects and why

| Data | What it is | Why | Legal basis (GDPR Art. 6) |
|---|---|---|---|
| Account | Email address, password (stored only as a hash by our database provider), account ID | Sign-in and keeping your data in your own account | Contract (b) |
| Trips | Start and end time, start and end address, coordinates, GPS route points, distance, trip type (business, commute, private), customer, purpose, notes | The mileage log and reports you use the app for | Contract (b) |
| Change history | For trips in a locked month: which field changed, old and new value, and when | Keeping a trustworthy record for tax purposes | Contract (b) and legitimate interest (f) in a reliable log |
| Vehicles | Name, licence plate, seat count, vehicle type, the car's Bluetooth name and identifier | Telling vehicles apart and recognising which car you are in | Contract (b) |
| Receipts | Photo of the receipt and the details read from it (amount, date and similar) | Attaching costs to trips | Contract (b) |
| Settings | Home and work address, reimbursement rate, company name and address, driver name, report options | Recognising commute trips and filling in the "potni nalog" report | Contract (b) |
| Subscription | Product, status, expiry date and Apple transaction ID of your subscription | Unlocking Paid features on your account | Contract (b) |
| Usage figures (optional) | Once a month, a range per metric (for example "11-15 automatic trips") | Setting the Free plan allowance and the price fairly | Consent (a) |

We do not use your data for advertising, we do not sell it, and we do not track you across other apps or websites. MileLog contains no third-party analytics or advertising code.

### Location, including in the background

If you turn on automatic detection and allow "Always" location access, MileLog watches for significant location changes in the background to notice when a drive starts. During a trip it uses GPS to measure the route and distance, and motion data (CoreMotion) on the device to confirm you are driving rather than walking. It also checks which Bluetooth audio device the phone is connected to, to recognise your car. Motion data and the Bluetooth check stay on the device; only the resulting trip is saved to your account. Without "Always" access you can still record trips manually while the app is open.

To show street addresses, MileLog sends trip coordinates to Apple's maps service (MapKit), which returns the address. Apple handles these requests under its own privacy policy.

### Receipts

Text on receipt photos is read on your iPhone with Apple's Vision framework. The photo and the details you save are uploaded to your account. Camera and photo library access is used only when you add a receipt.

### Subscriptions

Purchases are handled by Apple. We never see your card or payment details. When you subscribe or restore, the app sends Apple's signed transaction to our server, which checks it with Apple and records the subscription against your account. Your account ID is attached to the purchase (as Apple's "appAccountToken") so the subscription can be matched to your account. Apple also sends our server status updates (renewal, expiry, refund) for that transaction.

### Usage figures (only with your consent)

MileLog asks once whether you want to share anonymous usage figures. If you agree, after each month ends the app sends one range per metric for that month: automatic trips, report generations, receipt saves and month-end check opens. The server only adds 1 to a counter for that month, metric and range. The counters contain no account ID, device ID or location. The request is made from your signed-in session, so we describe it to Apple as data linked to you, but nothing in the stored counters identifies you. No feature depends on your answer. You can turn it off at any time in **Settings > Privacy > Share anonymous usage**; figures already counted cannot be separated out again because they are not linked to you.

### Data that stays on your iPhone

- The detection log (a technical record of how automatic detection behaved, kept for 7 days) stays on your device unless you choose to share it, for example by email when reporting a problem.
- Face ID or Touch ID app lock is handled entirely by iOS; MileLog never receives your biometric data.
- Notifications (to classify a trip, allowance heads-ups, month-end reminder) are scheduled locally on the device. MileLog does not use push notification servers.

## 3. Where your data is stored and who processes it

- **Supabase** (database, file storage, sign-in and server functions) stores your account data in the EU, in Supabase's Ireland region (eu-west-1). Supabase acts as our processor under a data processing agreement. Your data is protected by row-level security, so each account can only read its own records.
- **Apple** processes payments and subscriptions, provides the App Store, and returns addresses for coordinates (MapKit). For these, Apple acts under its own privacy policy.

We do not share your data with anyone else, except where the law requires it.

If a provider processes data outside the EU/EEA (for example for support or security), this is covered by the EU Standard Contractual Clauses or an adequacy decision. TODO: check the Supabase DPA and sub-processor list and keep this sentence accurate.

## 4. How long we keep data

- Account, trips, vehicles, receipts, settings, change history and subscription records: for as long as your account exists. You can delete individual trips, vehicles and receipts at any time. Note that Slovenian tax rules may require you to keep your own copy of mileage records for several years; export your reports before deleting.
- When you delete your account, all of the above is deleted from our database and storage straight away. Database backups held by Supabase are overwritten within TODO days (confirm Supabase backup retention for the plan used).
- Usage counters are aggregate and do not identify anyone; they are kept as long as they are useful.
- Apple keeps its own records of your purchases under its own policy.

## 5. Deleting your account

In the app go to **Settings > Account > Delete account**. This permanently deletes your account and all data stored in the cloud (trips, route points, vehicles, receipts and photos, settings, change history and subscription records). It cannot be undone.

Deleting your account does not cancel an Apple subscription. Cancel it in **Settings > [your name] > Subscriptions** on your iPhone, or in the App Store under your Apple Account, before or after deleting the account.

If you cannot use the app, email us (address in section 1) from the address on the account and we will delete it.

## 6. Your rights

Under the GDPR you have the right to:

- access your data and receive a copy;
- correct inaccurate data (most data can be edited directly in the app);
- delete your data;
- restrict or object to processing based on legitimate interest;
- data portability (the app can export your trips; ask us for anything else);
- withdraw consent for usage figures at any time in Settings > Privacy > Share anonymous usage, without affecting earlier processing.

To use these rights, email us. We reply within one month.

You can also complain to the Slovenian supervisory authority: **Informacijski pooblaščenec Republike Slovenije** (Information Commissioner of the Republic of Slovenia), Dunajska cesta 22, 1000 Ljubljana, gp.ip@ip-rs.si, www.ip-rs.si, or to the authority in the EU country where you live.

## 7. Security

Data travels encrypted (HTTPS). Access to the database is limited by row-level security to your own account. Purchase records can only be written by our server after checking Apple's signature. You can add Face ID or Touch ID protection to the app.

## 8. Children

MileLog is meant for adults who drive. It is not directed at children under 16, and we do not knowingly collect their data.

## 9. Changes

If this policy changes, we will update the date at the top and, for significant changes, tell you in the app. The current version is always at https://bobleeslo.github.io/milelog/privacy-policy.

## 10. Contact

TODO: contact email
