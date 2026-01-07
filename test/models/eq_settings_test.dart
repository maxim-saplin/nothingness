import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/eq_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults are disabled with zero gains', () {
    const s = EqSettings();
    expect(s.enabled, false);
    expect(s.gainsDb, const <double>[0, 0, 0, 0, 0]);
  });

  test('round-trips through json', () {
    const s = EqSettings(enabled: true, gainsDb: <double>[1, 2, 3, 4, 5]);
    final json = s.toJson();
    final restored = EqSettings.fromJson(json);
    expect(restored.enabled, true);
    expect(restored.gainsDb, const <double>[1, 2, 3, 4, 5]);
  });

  test('normalizes wrong-length gains to 5', () {
    final restored = EqSettings.fromJson(<String, dynamic>{
      'enabled': true,
      'gainsDb': <double>[9, 8],
    });
    expect(restored.enabled, true);
    expect(restored.gainsDb, const <double>[9, 8, 0, 0, 0]);
  });
}



