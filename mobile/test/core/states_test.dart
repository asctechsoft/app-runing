import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stride/presentation/common_components/states.dart';

/// T07: màn chặn Back phải có lối ra trên màn — ErrorState hiện cả Retry và nút thoát.
void main() {
  testWidgets('ErrorState có Retry + lối ra; bấm lối ra gọi onExit', (tester) async {
    var exited = 0;
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(title: 'T', message: 'M', onRetry: () => retried++, exitLabel: 'Back to Home', onExit: () => exited++),
        ),
      ),
    );
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Back to Home'));
    await tester.tap(find.text('Try again'));
    expect((exited, retried), (1, 1));
  });

  testWidgets('không truyền lối ra thì không hiện nút thứ hai (không nút giả)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(title: 'T', message: 'M', onRetry: () {}),
        ),
      ),
    );
    expect(find.byType(TextButton), findsNothing);
  });
}
