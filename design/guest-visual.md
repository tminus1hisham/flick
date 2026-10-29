# Guest mode: visual implementation

Companion to guest.md. Session, routing and persistence remain owned by their
existing controllers. Add no packages or theme tokens.

## Shared actions

Import `account.dart` in Title and Detail.

Use this pair of controls in a wrapping row. Each control is 48dp, with an 8dp
gap. Off icons use textPrimary; selected icons use accent; surfaces use
surface1. Do not add lock badges, counts or visible action labels.

```dart
Wrap(
  spacing: FlickTokens.grid * 2,
  runSpacing: FlickTokens.grid * 2,
  children: [
    ToggleAction(
      on: favourite,
      icon: Icons.favorite_border_rounded,
      onIcon: Icons.favorite_rounded,
      label: 'Add to favourites',
      onLabel: 'Remove from favourites',
      onPressed: onFavourite,
    ),
    ToggleAction(
      on: liked,
      icon: Icons.thumb_up_outlined,
      onIcon: Icons.thumb_up_rounded,
      label: 'Like title',
      onLabel: 'Unlike title',
      onPressed: onLike,
    ),
  ],
)
```

`favourite`, `liked`, `onFavourite` and `onLike` above are placement placeholders:
bind them to the screen's saved state and handlers.

ToggleAction provides press scale 0.97 and an icon cross-fade with scale
0.9 → 1, using stateDuration and the existing curves. Reduced motion removes
scale and retains the cross-fade. Its semantics expose the current toggled
state and the next action. Haptics follow an activated state change: light
impact for on, selection click for off.

Keep each toggle mounted while its state changes; do not key the whole
ToggleAction by its selected value.

## Title hero: Discover

Place the action row immediately after the description/loading section in
`_hero`, inside its existing padded Column. Use 16dp above and 4dp below.
Keep the row outside the meta-loading conditional so guests can save the
preview while metadata is loading or unavailable.

Bind the row through ListenableBuilder to `saved`; also rebuild when the
session changes. Guests always see off states, including after signing out.

```dart
const SizedBox(height: FlickTokens.grid * 4),
ListenableBuilder(
  listenable: Listenable.merge([saved, session]),
  builder: (context, _) {
    final p = widget.preview;
    return Wrap(
      spacing: FlickTokens.grid * 2,
      runSpacing: FlickTokens.grid * 2,
      children: [
        ToggleAction(
          on: session.loggedIn && saved.isFavourite(p.id),
          icon: Icons.favorite_border_rounded,
          onIcon: Icons.favorite_rounded,
          label: 'Add to favourites',
          onLabel: 'Remove from favourites',
          onPressed: () async {
            if (!await requireSignIn(context, Gate.favourite)) return;
            if (!context.mounted) return;
            saved.toggleFavourite(p);
          },
        ),
        ToggleAction(
          on: session.loggedIn && saved.isLiked(p.id),
          icon: Icons.thumb_up_outlined,
          onIcon: Icons.thumb_up_rounded,
          label: 'Like title',
          onLabel: 'Unlike title',
          onPressed: () async {
            if (!await requireSignIn(context, Gate.like)) return;
            if (!context.mounted) return;
            saved.toggleLike(p.id);
          },
        ),
      ],
    );
  },
),
const SizedBox(height: FlickTokens.grid),
```

The saved controller notifies listeners after each change. Opening or
dismissing a gate does not change the icon.

## Detail hero: Jellyfin

Place the shared action row after the hero artwork/title block and before
the existing playable-only Play / Download section. It must also appear on
Series titles.

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(
    FlickTokens.pageGutter,
    FlickTokens.grid * 4,
    FlickTokens.pageGutter,
    0,
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Insert the shared action row here.
      if (saveError != null) ...[
        const SizedBox(height: FlickTokens.grid * 2),
        Semantics(
          liveRegion: true,
          child: Text(
            "Couldn't save. Try again.",
            style: FlickText.metadata.copyWith(
              color: context.flick.danger,
            ),
          ),
        ),
      ],
    ],
  ),
),
```

`saveError` represents the screen controller's existing save-error state.
Initial values come from Item.isFavorite and Item.liked. Each handler clears
the error, flips its own state immediately and sends the request. A failure
reverts that toggle and exposes the inline error.

Keep the row visible during requests. Prevent duplicate writes for the same
toggle in its handler while allowing the other toggle to work. Preserve the
48dp layout when disabled.

Replace the existing raw black BackButton background with:

```dart
FlickTokens.background.withValues(alpha: 0.45)
```

## Login: guest link and pushed close button

Determine route mode once per build:

```dart
final pushed = ModalRoute.of(context)?.canPop ?? false;
```

On the first-launch home route, insert the guest link directly after the
primary Sign in button, before “Stream a link instead”. Keep its quiet
appearance consistent with that existing link.

```dart
if (!pushed && !session.onboarded) ...[
  const SizedBox(height: FlickTokens.grid),
  TextButton(
    style: TextButton.styleFrom(
      foregroundColor: FlickTokens.textSecondary,
      minimumSize: const Size.fromHeight(FlickTokens.minTouchTarget),
    ),
    onPressed: _busy ? null : () => session.continueAsGuest(),
    child: const Text('Continue as guest'),
  ),
],
```

For a pushed Login, add this as the last child of the existing body Stack,
outside the keyboard-adjusted form. It stays at the same position as Title's
back control.

```dart
if (pushed)
  Positioned(
    top: MediaQuery.paddingOf(context).top + FlickTokens.grid,
    left: FlickTokens.grid * 2,
    child: IconButton(
      tooltip: 'Close sign in',
      style: IconButton.styleFrom(
        backgroundColor: FlickTokens.background.withValues(alpha: 0.45),
      ),
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.close_rounded),
    ),
  ),
```

The close button remains available while submitting. Existing mounted checks
protect completion after dismissal. Successful pushed login pops to its
origin; the waiting gated handler performs the original action.

Keep the poster wall and existing scrolling form. Add no fixed height or
single-line restriction to the guest link.

## ProfileButton: guest sheet

Capture the ProfileButton's page context before opening the sheet. Use the
existing member content when signed in; otherwise use the following builder.
Use the same sheetAnimationStyle selection as requireSignIn, including
AnimationStyle.noAnimation under reduced motion.

```dart
builder: (sheet) => SafeArea(
  top: false,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(
      FlickTokens.pageGutter,
      FlickTokens.grid,
      FlickTokens.pageGutter,
      FlickTokens.pageGutter,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Not signed in',
          style: FlickText.railHeading.copyWith(
            color: FlickTokens.textPrimary,
          ),
        ),
        const SizedBox(height: FlickTokens.grid * 2),
        Text(
          'Browse and play as a guest. Sign in with your Jellyfin '
          'server account to save favourites, like titles and download.',
          style: FlickText.body.copyWith(
            color: FlickTokens.textSecondary,
          ),
        ),
        const SizedBox(height: FlickTokens.grid * 6),
        FilledButton(
          onPressed: () => Navigator.pop(sheet, true),
          child: const Text('Sign in'),
        ),
      ],
    ),
  ),
),
```

Open this guest sheet as `showModalBottomSheet<bool>`. After it resolves,
launch Login using the captured page context:

```dart
if (go == true && context.mounted) {
  await openSignIn(context);
}
```

This avoids pushing Login from a sheet context that is being disposed.
Dragging or tapping the barrier dismisses the profile sheet normally.

## Downloads prompt

Use SignInPrompt only after downloads have loaded, when the user is a guest
and the list is empty. Existing downloaded files retain the normal list and
play controls. The prompt replaces the empty-state body below the Downloads
app bar; it does not introduce another page or sheet.

## Tokens, icons and layout checks

- Favourites: favorite_border_rounded → favorite_rounded.
- Likes: thumb_up_outlined → thumb_up_rounded.
- Downloads prompt and gate: download_outlined.
- Login close: close_rounded, tooltip “Close sign in”.
- Main copy: textPrimary; supporting copy: textSecondary.
- Selected toggle: accent; inline save error: context.flick.danger.
- Sheet: existing surface1 theme, modalRadius and drag handle.
- Insets: pageGutter; gaps: multiples of grid.
- Sheet heading: pageTitle; profile heading: railHeading.
- Supporting copy: body; save error: metadata.
- Sheet buttons use the existing FilledButton and TextButton themes.
- No extra spinner or loading state is needed for these three components.

Verify at 360×640dp and 1.3× text: the gate fits without scrolling, headings
and supporting text wrap, and both buttons remain visible. Check each gate,
drag dismissal, keyboard-open Login, reduced motion, spoken toggle state and
the inline failure announcement.

Run the repository design gate after integration:

`python ~/.claude/skills/build-mobile/scripts/gates.py .`
