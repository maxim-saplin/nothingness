# Nothingness Documentation

Welcome to the documentation for the Nothingness project.

## 📚 Contents

- **Architecture**
  - [System Overview](architecture/overview.md) - High-level system design and components.
  - [Audio Playback & Spectrum](architecture/audio-playback-spectrum.md) - In-depth audio pipeline and visualization flows.
  - [Library Browsing](architecture/library-browsing.md) - MediaStore-driven folder navigation architecture, including the Android folder repair flow.
  - [UI Scaling](architecture/ui-scaling.md) - Implementation details of the global UI scaling solution.
  - [Skins](architecture/skins.md) - Visual skins and layouts.

- **Standards & Rules**
  - [Testing Standards](../.cursor/rules/testing-standards.mdc) - Requirements and guidelines for testing.
  - [Documentation Rules](../.cursor/rules/documentation.mdc) - When and how to write documentation.

- **Testing & Diagnostics**
  - [Device/emulator integration testing (no audio files)](device-testing.md) - Integration tests + deterministic playback harness (Android + macOS; target selection matters).
  - [Agent-driven debugging via VM service extensions](agent-driven-debugging.md) - Drive the live app from a script/agent (state queries, playback, audio-interruption simulation, diagnostics export).
  - [Emulator power diagnostics (evidence → culprit)](emulator-power-diagnostics.md) - ADB-first runbook to find background CPU/services/wakelocks on the Android emulator.
  - [Zeekr DHU Status-Bar Contrast](zeekr/zeekr-dhu-status-bar-contrast.md) - Automotive status-bar scrim for OEM displays that ignore `SystemUiOverlayStyle`.
  - [Oppo Find N5: Playback session stuck](oppo-find-n5-playback-session-stuck.md) - Release-build case where media session stays in `state=NONE` and in-app Play becomes unresponsive until restart.

### Building for Release

To build a signed release APK or App Bundle, you must configure the signing keys.

1.  **Create `android/key.properties`:**
    Create a file named `key.properties` in the `android/` directory. This file is **ignored by git** to protect your secrets.

    ```properties
    storePassword=<your_store_password>
    keyPassword=<your_key_password>
    keyAlias=<your_key_alias>
    storeFile=<absolute_path_to_your_keystore.jks>
    ```
2.  **Run the Build:**
    - Arm64-only shrinked APK (current shipping target):
      ```bash
      flutter build apk --release
      ```
    - (Optional) App Bundle:
      ```bash
      flutter build appbundle
      ```


## 🤝 Contributing

When adding new features or modifying the architecture, please remember to:
1.  Update the relevant documentation.
2.  Add a new section if appropriate.
3.  Keep diagrams up to date.


