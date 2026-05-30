import 'package:nothingness/main.dart' as app;
import 'agent_service.dart';

/// Debug entrypoint for agent-driven automation: installs the VM-service
/// harness, then runs the normal production app. Launch with
/// `flutter run -t dev/main_debug.dart`.
void main() {
  AgentService.install();
  app.main();
}
