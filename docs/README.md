# Nothingness Documentation

Welcome to the documentation for the Nothingness project.

## 📚 Contents

- **Architecture**
  - [System Overview](architecture/overview.md) - High-level system design and components.
  - [Audio Playback & Spectrum](architecture/audio-playback-spectrum.md) - In-depth audio pipeline and visualization flows.
  - [Library Browsing](architecture/library-browsing.md) - MediaStore-driven folder navigation architecture.
  - [UI Scaling](architecture/ui-scaling.md) - Implementation details of the global UI scaling solution.
  - [Skins](architecture/skins.md) - Visual skins and layouts.

- **Standards & Rules**
  - [Testing Standards](../.cursor/rules/testing-standards.mdc) - Requirements and guidelines for testing.
  - [Documentation Rules](../.cursor/rules/documentation.mdc) - When and how to write documentation.

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


