import 'package:flick/addons.dart';
import 'package:flick/main.dart';
import 'package:flick/screens/account.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MetaPreview _kid = (id: 'tt0012349', type: 'movie', name: 'The Kid', poster: null, releaseInfo: '1921');

class _Addons extends Addons {
  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, int skip = 0}) async => const [];

  @override
  Future<Meta> meta(String type, String id) async => (
        id: id,
        type: type,
        name: 'The Kid',
        poster: null,
        background: null,
        logo: null,
        description: null,
        releaseInfo: '1921',
        runtime: null,
        imdbRating: null,
        genres: const <String>[],
        videos: const <Video>[],
      );
  @override
  List<Addon> streamSources(String type, String videoId) => const [];
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await saved.load();
    session.client = null;
    session.accounts = false;
    addons = _Addons();
  });

  test('accounts are off by default', () => expect(session.accounts, isFalse));

  testWidgets('with accounts off, anyone favourites and likes without a sign-in sheet', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: const TitleScreen(_kid)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add to favourites'));
    await tester.tap(find.bySemanticsLabel('Like title'));
    await tester.pumpAndSettle();
    expect(find.text(Gate.favourite.title), findsNothing);
    expect(saved.favourites, [_kid]);
    expect(saved.isLiked(_kid.id), isTrue);
    expect(find.bySemanticsLabel('Remove from favourites'), findsOneWidget);
  });

  testWidgets('with accounts off, the app opens on the shell with no profile button or sign-in prompt',
      (tester) async {
    await tester.pumpWidget(const FlickApp());
    await tester.pump();
    expect(find.byType(Shell), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing);
    expect(find.byType(ProfileButton, skipOffstage: false), findsNothing);
    expect(find.byType(SignInPrompt, skipOffstage: false), findsNothing);
  });
}
