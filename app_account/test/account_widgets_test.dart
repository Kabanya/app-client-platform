import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('email sign-in dialog renders password flow', (tester) async {
    final account = AccountClient.fromSupabaseClient(
      SupabaseClient(
        'http://localhost:54321',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Column(
                children: accountMaterialSignInActions(
                  context: context,
                  account: account,
                  redirectTo: 'pomodoist://login-callback',
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(find.text('Email sign in'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'bad@test');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Password is required.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'bad');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sign in failed:'), findsOneWidget);
  });
}
