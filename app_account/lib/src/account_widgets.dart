import 'package:flutter/material.dart';

import 'account_client.dart';
import 'account_models.dart';

class AccountOverviewPanel extends StatelessWidget {
  const AccountOverviewPanel({
    super.key,
    required this.overview,
    required this.configured,
    this.onRefresh,
    this.actions = const [],
  });

  final AccountOverview? overview;
  final bool configured;
  final VoidCallback? onRefresh;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final overview = this.overview;
    if (!configured) {
      return const _MessagePanel(
        title: 'Pomodoist account',
        message: 'Supabase is not configured for this build.',
      );
    }
    if (overview == null) {
      return _MessagePanel(
        title: 'Pomodoist account',
        message: 'Sign in to sync your apps.',
        onRefresh: onRefresh,
        actions: actions,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overview.profile.displayName ??
                            overview.profile.email ??
                            'Unified Account',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (overview.profile.email != null)
                        Text(
                          overview.profile.email!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh account',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> accountMaterialSignInActions({
  required BuildContext context,
  required AccountClient? account,
  required String redirectTo,
  String appleLabel = 'Apple',
  String googleLabel = 'Google',
  String emailLabel = 'Email',
}) {
  if (account == null || account.currentUserId != null) {
    return const [];
  }
  return [
    OutlinedButton.icon(
      onPressed: () => account.signInWithApple(redirectTo: redirectTo),
      icon: const Icon(Icons.apple),
      label: Text(appleLabel),
    ),
    OutlinedButton.icon(
      onPressed: () => account.signInWithGoogle(redirectTo: redirectTo),
      icon: const Icon(Icons.account_circle_outlined),
      label: Text(googleLabel),
    ),
    OutlinedButton.icon(
      onPressed: () => _showMaterialEmailSignIn(
        context: context,
        account: account,
        redirectTo: redirectTo,
      ),
      icon: const Icon(Icons.email_outlined),
      label: Text(emailLabel),
    ),
  ];
}

Future<void> _showMaterialEmailSignIn({
  required BuildContext context,
  required AccountClient account,
  required String redirectTo,
}) async {
  final input = await showDialog<_EmailSignInInput>(
    context: context,
    builder: (context) => const _EmailSignInDialog(),
  );
  if (input == null) {
    return;
  }
  try {
    switch (input.action) {
      case _EmailSignInAction.magicLink:
        await account.signInWithEmail(input.email, redirectTo: redirectTo);
        if (context.mounted) {
          _showAccountMessage(context, 'Magic link sent.');
        }
        return;
      case _EmailSignInAction.signIn:
        await account.signInWithPassword(
          email: input.email,
          password: input.password,
        );
        if (context.mounted) {
          _showAccountMessage(context, 'Signed in.');
        }
        return;
      case _EmailSignInAction.signUp:
        await account.signUpWithPassword(
          email: input.email,
          password: input.password,
          redirectTo: redirectTo,
        );
        if (context.mounted) {
          _showAccountMessage(context, 'Account created.');
        }
        return;
    }
  } catch (error) {
    if (context.mounted) {
      final label = switch (input.action) {
        _EmailSignInAction.magicLink => 'Magic link',
        _EmailSignInAction.signIn => 'Sign in',
        _EmailSignInAction.signUp => 'Sign up',
      };
      _showAccountMessage(context, '$label failed: $error');
    }
  }
}

void _showAccountMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(content: Text(message)),
  );
}

class _EmailSignInInput {
  const _EmailSignInInput({
    required this.email,
    required this.password,
    required this.action,
  });

  final String email;
  final String password;
  final _EmailSignInAction action;
}

enum _EmailSignInAction { magicLink, signIn, signUp }

class _EmailSignInDialog extends StatefulWidget {
  const _EmailSignInDialog();

  @override
  State<_EmailSignInDialog> createState() => _EmailSignInDialogState();
}

class _EmailSignInDialogState extends State<_EmailSignInDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Email sign in'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            autofocus: true,
          ),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _submit(_EmailSignInAction.magicLink),
          child: const Text('Send link'),
        ),
        TextButton(
          onPressed: () => _submit(_EmailSignInAction.signUp),
          child: const Text('Create account'),
        ),
        FilledButton(
          onPressed: () => _submit(_EmailSignInAction.signIn),
          child: const Text('Sign in'),
        ),
      ],
    );
  }

  void _submit(_EmailSignInAction action) {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty) {
      setState(() => _errorText = 'Email is required.');
      return;
    }
    if (action != _EmailSignInAction.magicLink && password.isEmpty) {
      setState(() => _errorText = 'Password is required.');
      return;
    }
    Navigator.of(context).pop(
      _EmailSignInInput(email: email, password: password, action: action),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.title,
    required this.message,
    this.onRefresh,
    this.actions = const [],
  });

  final String title;
  final String message;
  final VoidCallback? onRefresh;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.account_circle_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(message),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ],
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh account',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      ),
    );
  }
}

String formatAccountBytes(int bytes) {
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1048576) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
