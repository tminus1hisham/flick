typedef SubtitleAppearance = ({int size, bool background});
const defaultSubtitleAppearance = (size: 100, background: true);

bool validSubtitleAppearance(SubtitleAppearance value) =>
    value.size >= 75 && value.size <= 200 && value.size % 25 == 0;

/// One player's offsets: external files use their URL, embedded tracks their local ID.
/// Nothing is persisted, so a new video/source cannot inherit another video's timing.
class SubtitleTiming {
  SubtitleTiming(this.apply);
  final Future<void> Function(double seconds) apply;
  final _offsets = <String, int>{};
  Future<void> _pending = Future.value();
  int _revision = 0;
  String? key;
  int get milliseconds => _offsets[key] ?? 0;

  Future<void> select(String? value) {
    key = value;
    return _write(value, milliseconds, remember: false);
  }

  Future<void> set(int milliseconds) {
    if (key == null) return Future.value();
    return _write(key, milliseconds.clamp(-30000, 30000), remember: true);
  }

  void clear() { _offsets.clear(); key = null; _revision++; }

  Future<void> _write(String? target, int value, {required bool remember}) {
    final revision = ++_revision;
    final operation = _pending.then((_) async {
      if (revision != _revision) return;
      await apply(value / 1000);
      if (remember && revision == _revision && target != null) _offsets[target] = value;
    });
    // A failed application must not block later selections or Retry.
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
