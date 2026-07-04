# Forge Buddy

Forge Buddy is the iOS companion app for Forge. It records voice notes, transcribes them when speech recognition is available, and syncs the notes and audio back to a paired Forge desktop vault.

Forge Buddy is open source under the MIT License.

## What Forge Buddy Can Do

- Record voice notes on iPhone.
- Capture quick text notes.
- Start Markdown notes from lightweight templates.
- Record agent task briefs as Markdown work orders.
- Attach image media notes from the photo picker.
- Add and edit note tags for later sorting in Forge.
- Save playable local audio.
- Show transcripts after recording.
- Keep recordings locally when the desktop app is unavailable.
- Pair with Forge desktop by QR code.
- Sync recordings, transcripts, and folders into Forge.
- Create folders that can be reflected in the desktop vault.

## Current Status

Forge Buddy is early software. The recording, playback, transcription, local save, and Forge pairing foundations are in place, but the companion workflow is still being refined.

Implemented foundations:

- Native SwiftUI app.
- Voice recording and playback.
- Text, template, voice-recorded agent task, and media capture flows.
- Speech transcription.
- Local recordings list.
- QR-based pairing with Forge desktop.
- Manual and automatic sync paths.
- Folder creation support.

Planned or in progress:

- More reliable background/offline sync.
- Better conflict handling.
- More transcript and capture management tools.
- Stronger onboarding and connection status.
- More tests and contributor documentation.

## Development

Open the Xcode project or generate it from `project.yml` with XcodeGen.

```bash
xcodegen generate
xcodebuild -project ForgeBuddy.xcodeproj -scheme ForgeBuddy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## License

MIT License. See `LICENSE`.
