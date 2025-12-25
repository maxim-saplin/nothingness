# CI/CD & Release Process

## Pipelines

This project uses GitHub Actions for CI/CD.

### 1. CI (`.github/workflows/ci.yml`)
- **Trigger**: Runs on every push and pull request to `main`.
- **Jobs**:
  - Sets up Java 17 and Flutter.
  - Decodes the Android keystore from GitHub Secrets.
  - Runs `flutter test`.
  - Runs `flutter build apk --release`.
  - Uploads the APK as an artifact (`app-release.apk`) with 1-day retention.
- **Signing**:
  - Uses the `release` keystore if secrets are valid.
  - Falls back to `debug` signing if secrets are missing (e.g., in forks or invalid config), ensuring the build still passes.

### 2. Release (`.github/workflows/release.yml`)
- **Trigger**: Manual dispatch (`workflow_dispatch`).
- **Inputs**:
  - `tag_name` (optional): e.g., `v1.0.0`. If omitted, uses the version from `pubspec.yaml`.
- **Jobs**:
  - Builds the release APK (signed).
  - Renames the APK to `nothingness-android-<version>.apk`.
  - Creates a GitHub Release with the specified tag.
  - Uploads the APK asset to the release.

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






