# App Review Notes (MileLog, BT1.MileLog)

Paste the "Notes" section below into App Store Connect > App Review Information > Notes. Fill in the demo account under Sign-In Information.

## Sign-in information

- Username: TODO (demo account email, e.g. a dedicated review account)
- Password: TODO (set in App Store Connect only, not in this file)
- The demo account should contain at least one vehicle and a few sample trips (business, commute, private) in the current and previous month, with one receipt, so reports can be generated straight away. TODO: seed the demo account before submission.
- TODO: decide whether the demo account has a complimentary Paid entitlement or stays on Free (so the reviewer can test the purchase in sandbox). Recommended: keep it on Free.

## Notes

MileLog is a mileage log for drivers who claim business and commute mileage (Slovenian "potni nalog" report). It records car trips automatically or manually and syncs them to the user's account.

**Why background location ("Always") is needed**

The core feature is automatic trip recording: the user does not have to open the app before every drive. MileLog uses significant location changes in the background to notice that a drive has started, then GPS for the duration of the trip to measure the route and distance, and stops when the car has been stationary for a set time. CoreMotion confirms the user is driving (not walking), and the connected car Bluetooth audio device identifies which vehicle is used. Location is used only for recording trips; it is not used for ads or shared with third parties. Automatic detection is off until the user turns it on, and without "Always" access the app still works with manual recording while it is open. The UIBackgroundModes "location" entry exists only for this purpose.

**How to test**

1. Sign in with the demo account above.
2. Record a manual trip: open the **Record** tab, choose a vehicle, tap **Start trip**, move (or simulate a location route), then tap **Stop trip**. The trip appears in the **Trips** tab, where you can set type, customer and purpose.
3. Automatic detection: on the **Record** tab (or **Settings > Auto-detect trips**) turn on **Automatic detection** and allow "Always" location access. A drive is detected after the phone moves at driving speed; the trip ends a few minutes after the car stops, and a local notification asks the user to classify the trip. This needs a real drive, so we attached a **demo video of a recorded drive** (see App Review attachment) showing detection start, the trip in progress and the finished trip.
4. Reports: **Settings > Own-car monthly report** generates the monthly PDF (potni nalog) from the trips.
5. Receipts: open a trip and add a receipt photo; the text is read on the device.

**Subscriptions**

- Free plan with a monthly allowance of automatic trips; Paid subscription (monthly and yearly, 14-day free trial for new subscribers) via In-App Purchase.
- The subscription screen opens from **Settings > Plan > See what Paid adds**, and also when the Free allowance is used up on the Record tab.
- **Restore purchases** is in **Settings > Plan** and on the subscription screen.
- Links to the Privacy Policy and Terms of Use are on the subscription screen and under **Settings > Plan**.
- The purchase works in the sandbox environment; our server accepts Sandbox transactions.

**Account deletion**

**Settings > Account > Delete account** permanently deletes the account and all cloud data (trips, vehicles, receipts and photos, settings, purchase records). The screen reminds the user that an Apple subscription must be cancelled separately in Apple ID settings.

**Privacy**

No third-party analytics, ads or tracking. Optional anonymous monthly usage figures (count ranges only) are sent only after the user opts in, and can be turned off in **Settings > Privacy > Share anonymous usage**.

Contact for review questions: TODO (name, email, phone)

## Demo video checklist

Record on a real iPhone with screen recording, ideally while a passenger holds the phone. Keep it under about 3 minutes; trim waiting time.

- [ ] Start from the Record tab with **Automatic detection** on; show the location permission set to "Always" (iOS Settings > MileLog > Location) and the app's own explanation before the system prompt.
- [ ] Show the car's Bluetooth connection (Control Center or the vehicle name appearing in the app).
- [ ] Put the app in the background (home screen) before driving to show detection works without opening it.
- [ ] Drive: show the trip starting by itself (Record tab shows the trip in progress, with distance increasing).
- [ ] Stop and park; show the trip ending after the stationary timeout and the local notification to classify the trip.
- [ ] Open the notification, classify the trip (business, customer, purpose) and show it in the Trips list with the route map.
- [ ] Optional: show the monthly report PDF and the Plan section with Restore purchases.
- [ ] No other people's personal data, real customer names or a readable home address visible; use the demo account.
- [ ] Do not operate the phone while driving; the driver must not handle the phone.
- [ ] Upload the video as an attachment in App Review Information (or link it from the notes). TODO: attach the file.
