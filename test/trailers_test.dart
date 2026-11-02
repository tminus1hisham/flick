import 'package:flick/trailers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates and deduplicates trailer references without arbitrary protocols', () {
    expect(parseTrailers(null), isEmpty);
    expect(parseTrailers([
      {'source': 'P6AaSMfXHbA', 'type': 'Trailer'},
      {'ytId': 'P6AaSMfXHbA'},
      {'source': 'P6AaSMfXHbA', 'type': 'Clip'},
      {'source': '<script>'},
      {'url': 'javascript:alert(1)'},
      {'url': 'file:///video.mp4'},
      {'url': 'https://user:secret@example.test/trailer.mp4'},
      {'url': 'https://example.test/trailer.mp4'},
      123,
    ]), [(source: 'P6AaSMfXHbA', youtube: true), (source: 'https://example.test/trailer.mp4', youtube: false)]);
    expect(trailerLink((source: 'P6AaSMfXHbA', youtube: true)), 'https://www.youtube.com/watch?v=P6AaSMfXHbA');
  });
}
