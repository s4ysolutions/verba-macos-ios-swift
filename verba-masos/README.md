Building Verba for macOS
```bash
xcodebuild -project /Users/dsa/s4y/verba-apple/verba-apple.xcodeproj \
  -scheme verba-masos \
  -sdk macosx \
  -configuration Debug \
  build
```
Running Verba on macOS
```swift
xcodebuild -project /Users/dsa/s4y/verba-apple/verba-apple.xcodeproj \
  -scheme verba-masos \
  -sdk macosx \
  -configuration Debug \
  build && \
open "$(xcodebuild -project /Users/dsa/s4y/verba-apple/verba-apple.xcodeproj \
  -scheme verba-masos \
  -sdk macosx \
  -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | grep ' BUILT_PRODUCTS_DIR ' | awk '{print $3}')/Verba.app"
```
Or simply
```swift
xcodebuild -project /Users/dsa/s4y/verba-apple/verba-apple.xcodeproj \
  -scheme verba-masos \
  -sdk macosx \
  -configuration Debug \
  build && \
open ~/Library/Developer/Xcode/DerivedData/verba-apple-*/Build/Products/Debug/Verba.app
```