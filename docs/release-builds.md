# Enhanced release builds

Pushing `feature/enhanced` or manually running **Build All Platforms Release**
builds release artifacts from the same commit and Flutter 3.44.8 stable SDK:

| Target | Artifact |
| --- | --- |
| Android | Signed armeabi-v7a, arm64-v8a and x64 APKs |
| Windows | x64 ZIP, with application files directly inside (no nested ZIP) |
| macOS | Universal DMG, macOS 12+, ad-hoc signed, not notarized |
| iOS | Unsigned IPA, iOS 15+, requires user-provided signing for installation |
| Linux | x64 and arm64 DEB packages |

Filenames append `e` to the `pubspec.yaml` version. Installation identity remains
`com.lonstarcat.jhentai`. Android keeps the existing release signing identity;
this workflow does not switch to a debug key.

Only Android needs repository Secrets `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEY_PROPERTIES`. Supply plain Base64 of the keystore (line wrapping is
allowed) and Java-properties text containing `storePassword`, `keyPassword`,
`keyAlias`, and the correct `storeType`. The workflow replaces `storeFile` with
an ephemeral runner path. Values are never printed. Signing material is removed
after the build, including when compilation fails; no signing files are uploaded.

Artifacts are retained for seven days. Windows uploads the package directory so
GitHub creates a single downloadable ZIP; other jobs upload only explicit
APK/DMG/IPA/DEB files. No source snapshots, account databases, credentials, logs
or caches are included. The workflow uses read-only repository permissions,
does not create tags or Releases, and does not change the update feed.

The older `build_publish.yml` remains a separate upstream-style master/tag
release workflow. It is not triggered by an enhanced-branch push. Do not create
a version tag just to start this branch build.

Local helper checks: `python3 -m unittest discover -s tool/ci -p 'test_*.py'`.
No real keystore or comic library is used by these tests.
