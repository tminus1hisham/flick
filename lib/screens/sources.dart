import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ota_update/flutter_ota_update.dart';

import '../addons.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../kit/focus.dart';
import '../kit/tv_surface.dart';

/// D4 Sources: installed addons (bundled with switches, user-added with remove + inline Undo)
/// and an inline field to add one by its link.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Switch values awaiting `setEnabled`, so the switch moves on tap.
  final _pending = <String, bool>{};
  ({Addon addon, bool on, Object error})? _toggleError;

  /// User addons removed this visit, with their index among user rows; Undo lasts while on D4.
  final _removed = <Addon, int>{};

  /// Rows present on entry appear at once; ones added here fade in.
  final _initial = {for (final a in addons.all) a.id};

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _toggle(Addon a, bool on) async {
    HapticFeedback.selectionClick();
    setState(() {
      _pending[a.id] = on;
      _toggleError = null;
    });
    try {
      await addons.setEnabled(a, on);
    } catch (e) {
      if (mounted) setState(() => _toggleError = (addon: a, on: on, error: e));
    } finally {
      if (mounted) setState(() => _pending.remove(a.id));
    }
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await addons.add(_url.text.trim());
      if (!mounted) return;
      _url.clear();
    } on AddonException catch (e) {
      _error = switch (e.kind) {
        AddonError.invalid => "That isn't a Stremio addon link",
        // ponytail: the contract has no offline kind, so one sentence covers both causes.
        AddonError.unreachable => "Couldn't reach it. Check the link and your connection.",
        AddonError.duplicate => 'Already added',
        AddonError.server => "The addon's server had a problem. Try again in a moment.",
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(Addon a, int index) {
    setState(() => _removed[a] = index);
    addons.remove(a);
  }

  void _undo(Addon a) {
    setState(() => _removed.remove(a));
    addons.restore(a);
  }

  @override
  Widget build(BuildContext context) {
    final fade = MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.artworkFadeDuration;
    return Scaffold(
      appBar: context.tv ? null : AppBar(title: const Text('Sources'), toolbarHeight: 48),
      body: TvSurface(title: 'Sources', back: Navigator.canPop(context), child: ListenableBuilder(
        listenable: addons,
        builder: (context, _) {
          final all = addons.all;
          final user = all.where((a) => !a.bundled && !_removed.containsKey(a)).toList();
          for (final e in _removed.entries.toList()..sort((a, b) => a.value.compareTo(b.value))) {
            user.insert(e.value.clamp(0, user.length), e.key);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(0, 8, 0, 4 + MediaQuery.paddingOf(context).bottom),
            children: [
              const _Label('Built-in'),
              for (final a in all.where((a) => a.bundled)) ...[
                a.locked ? _LockedRow(a) : _switchRow(a),
                if (_toggleError case (:final addon, :final on, :final error) when addon == a)
                  _Inline(
                    message: friendlyError(error),
                    action: TvControl(child: TextButton(onPressed: () => _toggle(a, on), child: const Text('Retry'))),
                  ),
              ],
              const SizedBox(height: 8),
              const _Label('Added by you'),
              if (user.isEmpty)
                const _Row(
                  leading: Icon(Icons.link, color: FlickTokens.textSecondary),
                  title: 'No user-added sources',
                ),
              for (final (i, a) in user.indexed)
                if (context.tv)
                  RevealArea(child: TvControl(key: ValueKey(a.scopeId), child: TextButton(
                    onPressed: () => _removed.containsKey(a) ? _undo(a) : _remove(a, i),
                    child: _Row(title: _removed.containsKey(a) ? '${a.name} removed' : a.name,
                      subtitle: a.capability, trailing: Text(_removed.containsKey(a) ? 'Undo' : 'Remove')),
                  )))
                else AnimatedSwitcher(
                  duration: fade,
                  child: _removed.containsKey(a)
                      ? _UndoRow(a, key: ValueKey('undo ${a.id}'), onUndo: () => _undo(a))
                      : _FadeIn(
                          key: ValueKey(a.id),
                          duration: _initial.contains(a.id) ? Duration.zero : fade,
                          child: _Row(
                            title: a.name,
                            subtitle: a.capability,
                            trailing: TvControl(child: IconButton(
                              tooltip: 'Remove ${a.name}',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _remove(a, i),
                            )),
                          ),
                        ),
                ),
              const SizedBox(height: 12),
              _form(),
              const SizedBox(height: 24),
              const _Label('App updates'),
              const _UpdateRow(),
            ],
          );
        },
      )),
    );
  }

  Widget _switchRow(Addon a) {
    final on = _pending[a.id] ?? addons.isEnabled(a);
    return MergeSemantics(
      child: TvControl(child: InkWell(
        onTap: () => _toggle(a, !on),
        child: _Row(title: a.name, subtitle: 'Built-in · ${a.capability}', trailing: _Toggle(on)),
      )),
    );
  }

  Widget _form() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: Text('Add a source', style: FlickText.button.copyWith(color: FlickTokens.textPrimary))),
        const SizedBox(height: 4),
        Semantics(
          label: 'Addon link',
          child: TvControl(child: TextField(
            controller: _url,
            readOnly: _busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _add(),
            decoration: const InputDecoration(hintText: 'https://…/manifest.json'),
          )),
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: _error != null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                const Icon(Icons.error_outline, size: 16, color: FlickTokens.danger),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _error ?? 'Paste a stremio:// or manifest link',
                  style: FlickText.metadata.copyWith(
                    color: _error != null ? FlickTokens.danger : FlickTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TvControl(child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _add,
          child: Text(_busy ? 'Checking link…' : 'Add source'),
        )),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 0, FlickTokens.pageGutter, 4),
    child: Semantics(
      header: true,
      child: Text(text, style: (context.tv ? FlickTv.railHeading : FlickText.smallLabel).copyWith(color: FlickTokens.textSecondary)),
    ),
  );
}

/// A flat 64dp ledger row: name over supporting text, a 48dp control at the right.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.leading, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: context.tv ? 88 : 64),
    padding: EdgeInsets.fromLTRB(FlickTokens.pageGutter, context.tv ? 16 : 8, FlickTokens.pageGutter, context.tv ? 16 : 8),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FlickTokens.outline))),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: (context.tv ? FlickTv.card : FlickText.cardTitle).copyWith(color: FlickTokens.textPrimary)),
              if (subtitle != null)
                Text(subtitle!, style: (context.tv ? FlickTv.body : FlickText.metadata).copyWith(color: FlickTokens.textSecondary)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    ),
  );
}

class _LockedRow extends StatelessWidget {
  const _LockedRow(this.addon);
  final Addon addon;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '${addon.name}. Built-in, always enabled. ${addon.capability}',
    excludeSemantics: true,
    child: _Row(
      title: addon.name,
      subtitle: 'Built-in · ${addon.capability}',
      trailing: const SizedBox.square(
        dimension: FlickTokens.minTouchTarget,
        child: Icon(Icons.lock_outline, size: 20, color: FlickTokens.textSecondary),
      ),
    ),
  );
}

class _UndoRow extends StatelessWidget {
  const _UndoRow(this.addon, {super.key, required this.onUndo});
  final Addon addon;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: _Row(
      title: '${addon.name} removed',
      trailing: TvControl(child: TextButton(
        onPressed: onUndo,
        child: Text('Undo', semanticsLabel: 'Undo removing ${addon.name}'),
      )),
    ),
  );
}

/// An inline error under a row, announced without moving focus.
class _Inline extends StatelessWidget {
  const _Inline({required this.message, required this.action});
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 4, FlickTokens.pageGutter, 4),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: FlickTokens.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: FlickText.metadata.copyWith(color: FlickTokens.danger))),
          action,
        ],
      ),
    ),
  );
}

/// 40×24 stadium switch in a 48dp box. Visual only: the row owns the tap.
class _Toggle extends StatelessWidget {
  const _Toggle(this.on);
  final bool on;

  @override
  Widget build(BuildContext context) {
    final d = MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.stateDuration;
    return Semantics(
      toggled: on,
      child: SizedBox.square(
        dimension: FlickTokens.minTouchTarget,
        child: Center(
          child: AnimatedContainer(
            duration: d,
            curve: FlickTokens.curveIn,
            width: 40,
            height: 24,
            padding: const EdgeInsets.all(3),
            decoration: ShapeDecoration(
              color: on ? FlickTokens.accent : FlickTokens.surface2,
              shape: StadiumBorder(side: on ? BorderSide.none : const BorderSide(color: FlickTokens.outline)),
            ),
            child: AnimatedAlign(
              duration: d,
              curve: FlickTokens.curveIn,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 18,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: on ? FlickTokens.onAccent : FlickTokens.textSecondary,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.duration, required this.child});
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: duration == Duration.zero ? 1 : 0, end: 1),
    duration: duration,
    curve: FlickTokens.curveIn,
    builder: (_, t, child) => Opacity(opacity: t, child: child),
    child: child,
  );
}

/// Checks GitHub Releases for a newer Flick, then downloads, verifies and opens the installer.
class _UpdateRow extends StatefulWidget {
  const _UpdateRow();

  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  final _ota = FlutterOtaUpdate(owner: 'tminus1hisham', repo: 'flick');
  bool _busy = false;
  OtaRelease? _release;
  double? _progress;
  String? _status;
  bool _failed = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await job();
    } on OtaException catch (e) {
      _failed = true;
      _status = switch (e.code) {
        'HTTP_ERROR' => "Couldn't reach GitHub, or there is no release yet.",
        'NO_ASSET' => 'The latest release has no APK.',
        'NO_CHECKSUM' => "The release can't be verified, so it was not installed.",
        'CHECKSUM_MISMATCH' => 'The download was corrupt. Try again.',
        'DOWNLOAD_FAILED' => 'The download failed. Check your connection.',
        _ => "Couldn't update. Try again.",
      };
    } catch (_) {
      _failed = true;
      _status = "Couldn't update. Try again.";
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _check() => _run(() async {
    final r = await _ota.checkForUpdate();
    _release = r;
    _status = r == null ? "You're on the latest version." : null;
  });

  Future<void> _install() => _run(() async {
    await _ota.downloadAndInstall(
      _release!,
      onProgress: (got, total) {
        if (mounted && total > 0) setState(() => _progress = got / total);
      },
    );
    _status = 'Opening the installer…';
  });

  @override
  Widget build(BuildContext context) {
    final r = _release;
    final subtitle = _busy && _progress != null
        ? 'Downloading ${(_progress! * 100).round()}%'
        : _busy
        ? (r == null ? 'Checking…' : 'Starting…')
        : r != null && _status == null
        ? 'Flick ${r.version} is available'
        : _status ?? 'Get new versions from GitHub';
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          _Row(
            title: r == null ? 'Check for updates' : 'Update to ${r.version}',
            subtitle: subtitle,
            trailing: TvControl(child: TextButton(
              onPressed: _busy ? null : (r == null ? _check : _install),
              child: Text(r == null ? 'Check' : (_failed ? 'Retry' : 'Install')),
            )),
          ),
        ],
      ),
    );
  }
}
