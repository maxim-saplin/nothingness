# CI/CD & Release Process

## Architecture

This project uses GitHub Actions for CI/CD with a reusable workflow architecture. All build logic is centralized in `.github/workflows/build-android.yml`, which is called by both CI and Release workflows.

### Reusable Workflow (`.github/workflows/build-android.yml`)

The reusable workflow contains all common build steps and optimizations:

- **Setup**:
  - Java 17 (Zulu distribution)
  - Android SDK Platform 33, NDK 27.0.12077973, CMake 3.22.1 (pre-installed)
  - Flutter (stable channel)
  - Android SDK caching (`~/.android`, `/usr/local/lib/android/sdk`)
  - Gradle caching (`~/.gradle/caches`, `~/.gradle/wrapper`)
- **Build Process**:
  - Decodes Android keystore from GitHub Secrets
  - Runs `flutter pub get`
  - Runs `flutter test`
  - Builds APK with `GRADLE_OPTS: "-Dorg.gradle.caching=true"` (arm64-only, code + resource shrinking enabled)
  - Renames APK to `nothingness-android-<version>.apk`
- **Post-build Actions** (conditional):
  - Upload artifact (if `upload-artifact: true`)
  - Create GitHub release (if `create-release: true`)

**Inputs**:
- `upload-artifact`: Upload APK as artifact (boolean)
- `create-release`: Create GitHub release (boolean)
- `release-tag`: Tag name for release (string, e.g., `v1.0.0`)
- `release-version`: Version string for release (string)

**Outputs**:
- `apk-path`: Path to the built APK
- `version`: Extracted version from `pubspec.yaml`

## Pipelines

### 1. CI (`.github/workflows/ci.yml`)
- **Trigger**: Runs on every push and pull request to `main`, or manual dispatch.
- **Job**: Calls `build-android.yml` with `upload-artifact: true`.
- **Result**: Uploads the APK artifact (`nothingness-android-<version>.apk`, ~20MB, arm64-only) with 1-day retention.

### 2. Release (`.github/workflows/release.yml`)
- **Trigger**: Manual dispatch (`workflow_dispatch`).
- **Jobs**:
  1. `check-release`: Extracts version from `pubspec.yaml`, checks if release tag already exists.
  2. `release`: Calls `build-android.yml` with `create-release: true` and the extracted tag/version.
- **Result**: Creates a GitHub Release with the tag `v<version>` and uploads the APK asset.

### 3. Emulator power regression (`.github/workflows/emulator-power-regression.yml`)
- **Trigger**: Manual dispatch and nightly schedule.
- **Job**:
  - boots Android emulator (API 33)
  - builds + installs debug APK
  - runs `tool/power/emulator_power_regression.sh --ci --window-sec 120 --sample-sec 5`
  - uploads `.tmp/power/` artifacts
- **Result**: Provides a threshold-based signal for idle background CPU/churn regressions before they become user-visible battery issues.

## Signing Configuration

To sign release builds, the following **Repository Secrets** must be configured in GitHub:

1.  **`STOREFILE`**: The Base64 encoded content of the `.jks` keystore file.
    -   **Important**: Must be a single line without newlines.
    -   **Mac/Linux Command**:
        ```bash
        base64 -i path/to/keystore.jks | tr -d '\n' | pbcopy
        ```
2.  **`STOREPASSWORD`**: The password for the keystore.
3.  **`KEYPASSWORD`**: The password for the key alias.
4.  **`KEYALIAS`**: The alias name of the key.

### Local Signing
To sign builds locally:
1.  Create `android/key.properties` (this file is `.gitignored`).
2.  Add the following content:
    ```properties
    storePassword=<your-store-password>
    keyPassword=<your-key-password>
    keyAlias=<your-key-alias>
    storeFile=<path-to-keystore.jks>
    ```






