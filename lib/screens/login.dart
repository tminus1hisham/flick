import 'package:flutter/material.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'torrent.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  Object? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var server = _server.text.trim();
      if (!server.startsWith('http')) server = 'http://$server';
      await session.login(server, _user.text.trim(), _pass.text);
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 24, FlickTokens.pageGutter, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const FlickMark(size: 40),
                    const SizedBox(width: 12),
                    Text('Flick', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 40),
                  Text('Sign in to your server', style: text.titleLarge?.copyWith(fontSize: 28, height: 34 / 28)),
                  const SizedBox(height: 8),
                  Text('Use your Jellyfin server address and account.',
                      style: text.bodyMedium?.copyWith(color: secondary)),
                  const SizedBox(height: 32),
                  _Field(
                    'Server',
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'http://192.168.1.10:8096'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    'Username',
                    TextField(controller: _user, textInputAction: TextInputAction.next),
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    'Password',
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.error_outline, size: 20, color: context.flick.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(friendlyError(_error!),
                            style: text.bodyMedium?.copyWith(color: context.flick.danger)),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => openMagnet(context),
                    icon: const Icon(Icons.link),
                    label: const Text('Stream a link'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label above a filled field. The theme's outline border would float a labelText onto the
/// field's edge, so the label sits outside and is handed to the field's semantics instead.
class _Field extends StatelessWidget {
  const _Field(this.label, this.field);
  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(height: 8),
          Semantics(label: label, child: field),
        ],
      );
}
