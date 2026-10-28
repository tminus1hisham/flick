import 'package:flutter/material.dart';

import '../state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
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
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 48),
              Text('Flick', style: Theme.of(context).textTheme.displaySmall),
              const Text('Sign in to your Jellyfin server'),
              const SizedBox(height: 32),
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'Server', hintText: 'http://192.168.1.10:8096'),
              ),
              TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username')),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
                    : const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
}
