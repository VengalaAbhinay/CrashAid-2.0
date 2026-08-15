import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crashaid/main.dart';

void main() {
  testWidgets('App launches smoke test', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(      // ← this line is the fix
        child: CrashAidApp(),
      ),
    );
    await tester.pump();
  });
}