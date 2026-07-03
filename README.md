# Forge Buddy

Forge Buddy is the iOS companion app for Forge. It pairs with the desktop app, records voice notes, stores playable audio, transcribes recordings when speech recognition is available, and syncs notes and folders into the local Forge vault on the Mac.

## Build

Open `ForgeBuddy.xcodeproj` in Xcode, or generate it from `project.yml` with XcodeGen.

```bash
xcodegen generate
xcodebuild -project ForgeBuddy.xcodeproj -scheme ForgeBuddy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
