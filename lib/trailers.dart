import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef Trailer = ({String source, bool youtube});

List<Trailer> parseTrailers(Object? raw) {
  if (raw is! List) return const [];
  final found = <Trailer>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final kind = item['type'];
    if (kind != null && kind != 'Trailer') continue;
    final id = item['ytId'] ?? item['source'];
    if (id is String && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      found.add((source: id, youtube: true));
    } else {
      final url = item['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty && uri.userInfo.isEmpty) {
        found.add((source: uri.toString(), youtube: false));
      }
    }
  }
  return found.toList();
}

String trailerLink(Trailer trailer) => trailer.youtube
    ? 'https://www.youtube.com/watch?v=${trailer.source}' : trailer.source;

/// Previews never enter movie playback, history, PiP or Up Next.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview(this.trailer, {required this.onEvent, super.key});
  final Trailer trailer;
  final ValueChanged<String> onEvent;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> {
  MethodChannel? _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AndroidView(
    viewType: 'flick/trailer',
    creationParams: {'source': widget.trailer.source, 'youtube': widget.trailer.youtube},
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: (id) {
      _channel = MethodChannel('flick/trailer/$id')..setMethodCallHandler((call) async {
        if (mounted && call.method == 'event' && call.arguments is String) widget.onEvent(call.arguments as String);
      });
    },
  );
}
