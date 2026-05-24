// Coverage for B-017: OWN-mode permission gate must depend ONLY on the audio
// permission. Mic and storage must not appear in the request list, and a denied
// mic must NOT block library access.
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('LibraryController OWN-mode permission gate (B-017)', () {
    test(
      'ownModePermissionList does NOT include microphone or storage',
      () {
        final permissions = LibraryController.ownModePermissionList;

        expect(
          permissions.contains(Permission.microphone),
          isFalse,
          reason: 'Mic is a BACKGROUND-mode dependency, not OWN-mode.',
        );
        expect(
          permissions.contains(Permission.storage),
          isFalse,
          reason:
              'Permission.audio covers READ_MEDIA_AUDIO (33+) and is mapped '
              'to READ_EXTERNAL_STORAGE on 29-32 internally by '
              'permission_handler — minSdk is now 29.',
        );
        expect(
          permissions.contains(Permission.audio),
          isTrue,
          reason: 'Audio is the only permission required for OWN-mode library.',
        );
      },
    );

    test('hasPermission is true when audio is granted regardless of mic', () {
      final hasPermission = LibraryController.computeOwnModeHasPermission({
        Permission.audio: PermissionStatus.granted,
        Permission.microphone: PermissionStatus.denied,
      });
      expect(hasPermission, isTrue);
    });

    test('hasPermission is true when audio granted and mic permanently denied',
        () {
      final hasPermission = LibraryController.computeOwnModeHasPermission({
        Permission.audio: PermissionStatus.granted,
        Permission.microphone: PermissionStatus.permanentlyDenied,
      });
      expect(hasPermission, isTrue);
    });

    test('hasPermission is false when audio is denied', () {
      final hasPermission = LibraryController.computeOwnModeHasPermission({
        Permission.audio: PermissionStatus.denied,
      });
      expect(hasPermission, isFalse);
    });

    test('hasPermission is false when audio is permanently denied', () {
      final hasPermission = LibraryController.computeOwnModeHasPermission({
        Permission.audio: PermissionStatus.permanentlyDenied,
      });
      expect(hasPermission, isFalse);
    });

    test('hasPermission is false when audio status is missing from map', () {
      final hasPermission =
          LibraryController.computeOwnModeHasPermission(<Permission,
              PermissionStatus>{});
      expect(hasPermission, isFalse);
    });
  });
}
