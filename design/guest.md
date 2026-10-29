# Optional sign-in (guest mode): brief + spec delta

User request (2026-10-29): "make the login or sign in optional so that users can use the app without registering but if they want to use features such as adding to favourites, liking, commenting or downloading they have to sign in first."

User decisions (asked 2026-10-29):
- **Comments: left out.** Neither Jellyfin nor Stremio addons have comments and Flick has no backend. Revisit when one exists.
- **Favourites and likes: Jellyfin + device.** Jellyfin titles save to the Jellyfin account (`/UserFavoriteItems/{id}`, `/UserItems/{id}/Rating`). Discover (addon) titles save on this phone. Both need sign-in.
- **First launch: sign-in screen + "Continue as guest".** After that, guests open straight into Discover.

"Sign in" means signing in to a Jellyfin server, the only account Flick has.

## 1. Brief delta (UX, Claude)

### Users and jobs
- **Guest**: just installed; has no Jellyfin server or doesn't want to type one in yet. Job: browse Discover, open a title, play a stream. Never blocked from that.
- **Member**: signed in. Job as before, plus: keep a title for later (favourite), mark one they enjoyed (like), download for offline.

### What a guest can and can't do
| Feature | Guest | Member |
|---|---|---|
| Discover, Title, Streams, Sources, playback (addon + torrent) | yes | yes |
| Home, Browse, Search (Jellyfin library) | not shown: there is no server | yes |
| Favourite / like a Discover title | gated → sign-in sheet | yes, saved on device |
| Favourite / like a Jellyfin title | n/a (no Jellyfin titles visible) | yes, saved to Jellyfin |
| Download | gated: Downloads tab shows the sign-in prompt | yes (Jellyfin titles, as today) |
| Already-downloaded files (from an earlier sign-in) | still listed and playable | yes |

### Screen inventory (delta)
1. **Login (existing, poster wall)**: gains a quiet **"Continue as guest"** link under the primary button, shown only on first launch (when it is the app's home). When opened from a gate it is a pushed route: a close button replaces the link, and a successful sign-in pops back to where the user was.
2. **Guest shell (new state of the existing Shell)**: two tabs, **Discover** and **Downloads**. No Home/Browse/Search: they would be three dead tabs.
3. **Sign-in sheet (new, kit-style bottom sheet)**: opened by a gated action. Names the reason ("Sign in to save favourites" / "… to like titles" / "… to download"), one line on what an account is ("Your Jellyfin server account. Favourites and downloads follow you."), primary **Sign in**, quiet **Not now**.
4. **Favourite + like toggles (new component)**: on the Title hero (Discover) and the Detail hero (Jellyfin).
5. **Guest Downloads prompt (new inline state)**: the Downloads empty state for guests: icon, "Sign in to download", one line, **Sign in** button. If old downloads exist, they list as normal (no prompt).
6. **Profile sheet (existing)**: for a guest it reads "Not signed in" with a **Sign in** button in place of "Signed in to … / Sign out".
7. **Favourites surfaces (new, minimal)**: Discover gets a leading **"Favourites"** chip in the catalog chip row (member only, only when the current type has saved titles). Home gets a **"Favourites"** poster row from Jellyfin.

### Flow map
```
first launch ──► Login ──Sign in──► Shell (5 tabs)
                   └──Continue as guest──► Guest shell (Discover · Downloads)
later launches:  member → Shell · guest → Guest shell (no login screen)
Sign out (profile) ─► Guest shell (not the login screen: guest is a normal state now)

Guest: Title ──tap ♥ / 👍──► Sign-in sheet ──Not now──► back on Title, nothing changed
                                  └──Sign in──► Login (pushed) ──success──► pops to Title,
                                                the tapped action is applied (♥ is now on)
                                                and the app underneath is the member Shell
Guest: Downloads tab ──Sign in──► Login (pushed) ──success──► member Shell
Guest: Profile ──Sign in──► Login (pushed)
```
Resume intent: the action that triggered the gate completes after sign-in. The user never taps it twice.

### State matrix (new pieces)
| Piece | Loading | Empty | Error | Offline | Success |
|---|---|---|---|---|---|
| Sign-in sheet | n/a | n/a | n/a | n/a (sign-in itself reports offline inline on Login, as today) | sheet closes |
| Login (pushed) | button busy, as today | n/a | inline error, as today | "Couldn't reach the server", as today | pops back, gated action applied |
| Toggle (Jellyfin) | optimistic: flips at once | n/a | reverts; inline "Couldn't save. Try again." under the action row, cleared on next tap; screen reader announces it | same as error | stays flipped |
| Toggle (Discover, device) | instant | n/a | n/a (local write) | n/a | flipped |
| Guest Downloads | n/a | sign-in prompt | n/a | n/a | existing list if old downloads exist |
| Discover Favourites chip | n/a | chip hidden | n/a | works offline (local) | grid of saved posters |
| Home Favourites row | part of Home's skeleton | row hidden | Home's error state | Home's offline shell | poster row |

### Interaction notes
- Gate = **bottom sheet**, not a dialog or snackbar (RULES). Drag to dismiss = Not now. Anchored to the bottom like every Flick sheet; `sheetDuration`, `curveIn`/`curveOut`.
- Toggle press: scale 0.97 on press-down (`stateDuration`), icon morphs outline→filled with a short scale pop (0.9→1.0, `stateDuration`, `curveIn`; no overshoot on reduced motion: cross-fade only). `HapticFeedback.lightImpact` on turning **on** only; selectionClick on turning off.
- Toggles are 48dp, with spoken labels that state the action and the state ("Add to favourites" / "Remove from favourites", `Semantics(toggled:)`).
- A guest sees the toggles in their normal "off" look. The gate opens on tap, so the feature is discoverable. No lock badges: they'd add noise to every title.

### Allowed to scroll
No change: Login (keyboard), Title, Detail, Home, Discover grid, Downloads list. The sign-in sheet must fit without scrolling at 360×640 and 1.3× text.

### Applied
- ui-ux-pro-max: touch targets ≥44/48dp; icon-only buttons have labels; loading feedback (optimistic toggles); bottom nav ≤5 and no dead tabs; predictable back (pushed login pops to origin); errors next to the control, not at the top.
- apple-design: Agency (Not now always available, guest is a first-class state, no forced path); Purpose (comments cut, nothing without a backend); feedback on press-down; harmony: haptic, icon morph and state change on the same frame; reduced motion → cross-fade; spatial consistency: the sheet leaves the way it came.
- emil-design-eng: scale 0.97 press; never animate from scale(0) (pop from 0.9); ease-out curves, UI motion under 300ms; the toggle is seen tens of times a day, so its motion is short and subtle; asymmetric haptics (on > off).

## 2. Spec delta (code contract)

### Session (lib/session.dart)
- `bool onboarded`: prefs `onboarded`. Set by `login()` and `continueAsGuest()`. `load()` treats an existing token as onboarded (existing installs skip the guest link).
- `logout()` keeps `onboarded`, so sign-out lands in the guest shell.
- New `Saved extends ChangeNotifier` (same file), global `saved` in state.dart: device favourites (`List<MetaPreview>`, newest first) and likes (`Set<String>` of Stremio ids) in shared_preferences. `isFavourite(id)`, `isLiked(id)`, `toggleFavourite(MetaPreview)`, `toggleLike(String id)`.

### Jellyfin (lib/jellyfin.dart)
- `Item.isFavorite` (`UserData.IsFavorite`), `Item.liked` (`UserData.Likes == true`).
- `setFavorite(id, bool)`: `POST|DELETE /UserFavoriteItems/{id}?userId=`.
- `setLiked(id, bool)`: on → `POST /UserItems/{id}/Rating?userId=&likes=true`; off → `DELETE /UserItems/{id}/Rating?userId=`.
- `items(favorites: true)` adds `filters=IsFavorite`.

### Routing (lib/main.dart)
`home`: loggedIn → (online ? Shell : OfflineShell); else onboarded → Shell(guest) ; else LoginScreen.
Guest Shell = Discover + Downloads tabs.

### Gate API (lib/screens/account.dart, new)
```dart
enum Gate { favourite, like, download }
/// True when signed in, now or after the sheet + login. The caller then performs the action.
Future<bool> requireSignIn(BuildContext context, Gate gate);
Future<bool> openSignIn(BuildContext context); // pushes LoginScreen as a route
class SignInSheet extends StatelessWidget   // pops true = Sign in
class ToggleAction extends StatefulWidget   // on, icon/onIcon, label/onLabel, onPressed
class SignInPrompt extends StatelessWidget  // guest Downloads empty state
```

### Motion
Only existing tokens: `stateDuration` (press + icon pop), `sheetDuration` + `curveIn`/`curveOut` (sheet, existing theme), page transition for pushed Login (existing). `MediaQuery.disableAnimationsOf` → no scale, cross-fade only.

## 3. Ponytail gate

Ultra (UX):
- cut: comments → no backend; nothing to store them in (user agreed).
- cut: Home/Browse/Search tabs for guests showing "sign in" walls → hidden; three dead tabs fail "where can I go".
- cut: lock badges on gated buttons → a normal off toggle + the gate on tap.
- cut: a separate "Favourites" screen/tab → a chip on Discover and a row on Home, where the titles already live.
- cut: dislike (Jellyfin's `Likes=false`) → like on/off only; the user asked for liking.
- cut: separate sign-up flow → Login's existing "Sign up isn't available yet" stays as is.
- kept: resume intent after sign-in, because tapping ♥ twice after a sign-in detour is the main friction of soft gates.
- kept: Downloads tab for guests, because old downloads must stay playable and it is where "download needs sign-in" is learned.
- kept: first-launch guest link on Login (user's choice).

Full (code):
- 1 new file (`lib/screens/account.dart`); everything else edits existing files.
- reuse: LoginScreen (route mode via `ModalRoute.canPop`), ProfileButton sheet, PosterRow, Discover's `_Poster` grid tile, shared_preferences.
- no new packages, no new tokens.
- ponytail: device favourites aren't keyed per account (single-user app). Key them by server+userId if a second account appears.
- known gap: Home's Favourites row refreshes on pull-to-refresh, not on return from Detail.
