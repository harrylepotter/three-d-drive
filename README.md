# Three D Drive

See what’s playing on Adelaide’s Three D Radio while listening on 93.7 FM. The iPhone app and touchscreen CarPlay widget show the matched cover, title and artist. Tap the heart to save the displayed recording to **liked from 3d radio**. Home Assistant fingerprints the station’s internet stream. The car supplies the audio through its FM tuner.

## Build and connect

1. Set up the relay, playlist add-on and drive package from the [companion repository](https://github.com/harrylepotter/three-d-radio-addons).
2. Use Xcode with the iOS 26 SDK or later. Register an app bundle identifier and its widget extension (the same identifier with `.heart` appended). Enable Push Notifications for both targets. The two targets share a device-only Keychain group.
3. From the repository root, set the server and bundle identifier for your build. Substitute your own HTTPS origin and app identifier in the example below. An HTTP origin over an encrypted private network such as Tailscale is also supported. The script writes the settings locally.
4. Open `ThreeDDrive.xcodeproj`, select your signing team for both targets, and run the **ThreeDDrive** scheme on the iPhone. Enter a Home Assistant access token on the phone. It is saved to Keychain.

```sh
python3 scripts/configure.py https://radio.example.invalid org.example.threedrive
```

## Use in the car

- In iPhone **Settings → General → CarPlay → your vehicle → Widgets**, add **Three D • Like this song**. Start a drive from the widget or the app. A match swaps in its artwork and heart. The heart always references the recording shown when you tapped.
- The widget labels an unconfirmed recording **Last heard** after 150 seconds and hides its heart after five minutes. Home Assistant requests a reload when the track changes. iOS schedules WidgetKit delivery.
- In **Shortcuts → Automation → CarPlay**, configure **Disconnects → Run Immediately → End Three D Drive** to end the session. The app also has an End drive button, and the server timer expires after two hours.
- For a rotary controller, add the start, like and end scripts from the drive package to Home Assistant Companion’s CarPlay Quick Access. That like action saves the current fresh match.

The development build uses sandbox APNs. The add-on needs its own app-scoped APNs key for server-triggered widget updates. See the [provider setup](https://github.com/harrylepotter/three-d-radio-addons#carplay). [Apple’s WidgetKit push documentation](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications)
