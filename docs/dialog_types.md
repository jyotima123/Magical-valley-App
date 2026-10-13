# Dialog & Onboarding Types

There are three distinct patterns for surfacing help, hints, and guided tours in this app. Pick the right one for the context.

---

## 1. Full-screen onboarding slideshow — `IntroductionScreen`

**Package:** `introduction_screen`  
**Used for:** First-time app onboarding (runs once on install, before login).  
**File:** `lib/modules/auth/onboarding_screen.dart`

### When to use
- The user has never seen the app before and needs a product tour *before* they can interact with anything.
- You need swipe-between-pages navigation, large hero images/icons, and a "Get Started" / "Skip" flow.
- The content is completely independent of the current screen state.

### How it works
```dart
IntroductionScreen(
  pages: [
    PageViewModel(title: '...', body: '...', image: ...),
  ],
  onDone: () => ...,
  onSkip: () => ...,
  done: const Text('Get Started'),
  next: const Icon(Icons.arrow_forward),
)
```

### Characteristics
- Full-screen route pushed via `Navigator.push` / `pushReplacement`.
- Each page has a large illustration area, a title, and a body paragraph.
- Progress shown as animated dots at the bottom.
- Built-in back/next/skip/done buttons — no custom state management needed.

---

## 2. Single-page hint dialog — `AppDialog`

**File:** `lib/widgets/app_dialog.dart`  
**Used for:** First-run feature hints triggered after a screen loads (e.g. the "Explore and follow channels" hint shown the first time you open the Channels screen).

### When to use
- You need to explain **one thing** with an icon, a heading, and an optional sub-heading.
- The dialog is modal — the user must dismiss it before continuing.
- Optionally auto-closes after a timeout (set `autoCloseDuration` + `dismissible: false`).

### How it works
```dart
await AppDialog.show(
  context: context,
  icon: Icons.explore,
  heading: 'Explore and follow channels',
  subheading: 'Use the Explore tab to follow channels and see their posts here.',
  dismissible: true,
);
```

### Characteristics
- Rendered as a centred `Dialog` with a rounded card.
- Icon displayed in a coloured rounded square (accent colour at 15 % opacity).
- An **OK** button closes the dialog; tap-outside also closes if `dismissible: true`.
- For first-run hints, the heading and subheading live in the `first_run_hints` table (migration 082), not in code. Add a row, a matching `FirstRunHintKeys` constant, then:
  ```dart
  await FirstRunService.instance.maybeShowHint(
    context,
    key: FirstRunHintKeys.myHint,
    icon: Icons.explore, // icons stay in code: release builds tree-shake icon fonts
  );
  ```
  The app stores the row's `content_updated_at` when the hint is shown. Editing the row's heading or subheading bumps that timestamp, so every user sees the hint again on their next visit.

---

## 3. In-place tour overlay — `AppTourOverlay` + `TourStep`

**File:** `lib/widgets/app_tour_overlay.dart`  
**Used for:** Contextual walkthroughs of a *live* screen — the UI beneath remains visible and, optionally, a spotlight highlights specific elements.

### When to use
- You want to guide the user through multiple elements **on the current screen** without leaving it.
- Optionally highlight individual widgets with a spotlight cutout.
- The tour can be triggered by a help button (`?`) or automatically on first use.

### How it works

#### 1. Define steps
```dart
const steps = [
  TourStep(
    title: 'Channel Name',
    body: 'The name followers will see everywhere in the app.',
    icon: Icons.store_outlined,
    // anchorProvider: optional — return a Rect to spotlight a widget.
    // Omit for a centred card with a full dark overlay.
  ),
  TourStep(
    title: 'Bio',
    body: 'Tell followers what your channel is about.',
    icon: Icons.info_outline,
  ),
];
```

#### 2. Add a boolean to your state
```dart
bool _showingTour = false;
```

#### 3. Place the overlay in the topmost Stack
```dart
Stack(
  children: [
    MyScreenContent(),
    if (_showingTour)
      AppTourOverlay(
        steps: steps,
        onStepShown: (index) { /* analytics */ },
        onFinish: () => setState(() => _showingTour = false),
        onSkip:   () => setState(() => _showingTour = false),
      ),
  ],
)
```

#### 4. Trigger it
```dart
IconButton(
  icon: const Icon(Icons.help_outline),
  onPressed: () => setState(() => _showingTour = true),
)
```

### Characteristics
- Dark scrim covers the whole screen; an optional rounded-rect **spotlight hole** reveals the targeted widget.
- A **tooltip card** appears above or below the anchor (auto-positioned to avoid clipping).
- Card shows: icon + title + body + progress dots + Next / Done button + Skip text.
- Animated dots show position in the sequence.
- Tapping the dark overlay triggers `onSkip`.
- `anchorProvider` is a `Rect? Function()` — use `GlobalKey` + `RenderBox.localToGlobal` to compute the live rect, or return `null` for a centred card (useful inside scrollable/sheet contexts where rects are hard to pin).

### Spotlight anchor example
```dart
final _myKey = GlobalKey();

TourStep(
  title: 'Save Button',
  body: 'Tap Save to apply your changes.',
  icon: Icons.save,
  anchorProvider: () {
    final box = _myKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final pos = box.localToGlobal(Offset.zero);
    return pos & box.size;
  },
)
```

---

## Choosing the right pattern

| Need | Use |
|---|---|
| First launch, before any interaction | `IntroductionScreen` |
| One-time hint for a single feature | `AppDialog` |
| Guided walkthrough of an active screen | `AppTourOverlay` + `TourStep` |
