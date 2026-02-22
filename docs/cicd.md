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
- **Nightly behavior**: Scheduled runs execute only when the repository has commits within the last 24 hours; otherwise the workflow skips the heavy emulator job.
- **Job**:
  - boots Android emulator (API 33)
  - builds + installs debug APK
  - runs `tool/power/emulator_power_regression.sh --ci --window-sec 120 --sample-sec 5`
  - uploads `.tmp/power/` artifacts
- **Result**: Provides a threshold-based signal for idle background CPU/churn regressions before they become user-visible battery issues.

#### How regression evaluation works

The regression script captures two windows and compares them:

- **S0 control window**: app is force-stopped and device is idle on home screen.
- **S1 idle-background window**: app is launched, then sent to home screen, then measured while idle in background.

The evaluator (`tool/power/evaluate_power_capture.py`) writes a `summary.json` artifact and, in CI strict mode (`--ci`), fails the job when violations are detected.

#### Failure criteria (strict mode)

The run fails if any of these are true:

- `median_delta > 0.8` **and** `s1_median > 0.8`
- `s1_p95 > 2.5`
- `s1_max_consecutive_gt4 >= 3`
- `log_churn_count > 10`

`active_wakelock` is currently warning-level only (reported, but not fail by itself).

#### How to read and treat results

1. Open **Actions → Emulator Power Regression** run.
2. Check top-level outcome:
   - **Green**: no threshold violations.
   - **Red**: either CI/infrastructure failure or threshold regression failure.
3. Download `emulator-power-regression-artifacts` and inspect `summary.json`.

Recommended triage:

- **Infra failure** (emulator boot/build/install/script crash): fix CI/environment first, then re-run.
- **Threshold failure** (`summary.json.status = fail`): treat as potential regression in background behavior; compare key metrics against recent passing runs before merging.
- **Warning only** (`warnings` non-empty, `status = pass`): track, but do not block by default.

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






