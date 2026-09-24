part of 'app_header_host.dart';

/// Runs the introductions for [AppHeaderHost].
///
/// A screen whose header names an [AppHeaderConfig.barTourId] gets the bar
/// introduced the first time it is opened in this browser: the window dims,
/// and one part of the bar at a time is lit and explained. A screen may offer
/// [AppHeaderConfig.tours] of its own parts as well, which run here too, one at
/// a time, the bar's first. They live in the host and not in the screen
/// because the bar's introduction starts by bringing the bar out of zen mode,
/// and only the host can.
///
/// **What is lit is live.** The show-bar stop asks for its button to be
/// pressed rather than offering a Next, and a lit control that takes the
/// reader somewhere else ends the introduction, because the screen stops
/// offering it. Everything outside the hole is out of reach, and the page is
/// taken out of the focus and semantics trees while one runs.
///
/// Seen is recorded however it ends: finished, skipped, Escape, or a lit
/// control that navigated. Without a registered [TourStore] (a widget test)
/// there is no introduction.
///
/// The host MUST call [_followTour] from its build, draw [_buildTour] on top
/// while [_touring], and report the bar through [_tourBarShown],
/// [_tourBarHidden] and [_tourBarSettled].
mixin _HostTour on State<AppHeaderHost> {

  /// The introduction's scrim fading in.
  static const Duration _tourFade = Duration(milliseconds: 200);

  /// How far the lit hole reaches past the part it shows.
  static const double _holeMargin = 6;

  /// Between the hole and the tip's beak.
  static const double _tipGap = 4;

  /// Keeps a tip off the window's edges.
  static const double _tipGutter = 16;

  /// Keeps the beak on the tip's straight edge, clear of its rounded corners.
  static const double _beakInset = kCardCornerRadius;

  /// The host's zen mode, which the bar's introduction starts from. Only ever
  /// written from here.
  set _zen(bool value);

  final TourTargetRegistry _tourTargets = TourTargetRegistry();

  /// The introduction running, or null while there is none.
  String? _tourId;

  /// The running introduction's stops, as the screen offered them in the last
  /// build. Empty while none runs.
  List<AppTourStop> _tourStops = const [];

  /// Which of its stops is showing.
  int _tourStop = 0;

  /// Set while the bar slides in after the first stop. The next part is still
  /// moving, so the scrim stays whole and no tip is drawn until it arrives.
  bool _tourSettling = false;

  /// Where the current stop's part is, measured after the frame that drew it.
  Rect? _tourRect;

  /// A start is already waiting for the end of the frame.
  bool _tourQueued = false;

  /// Read once: the shell registers it before the first frame, and a widget
  /// test that registers none gets no introductions.
  late final TourStore? _tours = GetIt.I.isRegistered<TourStore>() ? GetIt.I<TourStore>() : null;

  bool get _touring => _tourId != null;

  @override
  void initState() {
    super.initState();
    // Forgetting what was seen offers the current screen's introduction again
    // straight away, which is what the debug menu's reset is for.
    _tours?.addListener(_toursChanged);
  }

  @override
  void dispose() {
    _tours?.removeListener(_toursChanged);
    super.dispose();
  }

  void _toursChanged() {
    if (mounted) setState(() {});
  }

  /// Starts or ends an introduction to match what [config] now offers, and
  /// measures the part it points at.
  ///
  /// Called from build, so every change waits for the end of the frame. That is
  /// also the first moment the part has a place on screen to measure. A part
  /// that is still moving (a step sliding in) is measured again on the frame
  /// after, for as long as its place keeps changing.
  void _followTour(BuildContext context, AppHeaderConfig? config) {
    final offered = config == null ? const <AppTour>[] : _toursFor(context, config);
    final running = offered.where((tour) => tour.id == _tourId).firstOrNull;
    _tourStops = running?.stops ?? const [];

    if (_tourId != null) {
      // No longer offered: a lit control took the reader somewhere else.
      _afterFrame(running == null ? _endTour : _measureTour);
      return;
    }

    final tours = _tours;
    if (tours == null || _tourQueued) return;
    final next = offered.where((tour) => !tours.hasSeen(tour.id)).firstOrNull;
    if (next == null) return;
    _tourQueued = true;
    _afterFrame(() => _startTour(next));
  }

  /// Every introduction [config] offers, the bar's first.
  List<AppTour> _toursFor(BuildContext context, AppHeaderConfig config) => [
    if (config.barTourId case final String id) AppTour(id, _barStops(context, config)),
    ...config.tours,
  ];

  /// Every part of the bar [config] introduces, left to right once the bar is
  /// out. The show-bar button comes first because nothing else is on screen
  /// until it is pressed, and the hide button last because pressing it ends
  /// the introduction.
  List<AppTourStop> _barStops(BuildContext context, AppHeaderConfig config) => [
    if (config.offersZen) AppTourStop(AppHeaderPart.showBar, context.localizations.appHeader_tourShowBar),
    for (final (index, crumb) in config.crumbs.indexed)
      if (crumb.tip case final String tip) AppTourStop((AppHeaderPart.crumb, index), tip),
    if (config.trailingTip case final String tip) AppTourStop(AppHeaderPart.trailing, tip),
    AppTourStop(AppHeaderPart.settings, context.localizations.appHeader_tourSettings),
    if (config.offersZen) AppTourStop(AppHeaderPart.hideBar, context.localizations.appHeader_tourHideBar),
  ];

  void _afterFrame(VoidCallback callback) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback();
      });

  void _startTour(AppTour tour) {
    _tourQueued = false;
    setState(() {
      _tourId = tour.id;
      _tourStop = 0;
      _tourRect = null;
      _tourSettling = false;
      // The bar's introduction is the way out of zen mode, so it starts there.
      if (tour.stops.firstOrNull?.target == AppHeaderPart.showBar) _zen = true;
    });
  }

  void _measureTour() {
    if (_tourId == null || _tourSettling) return;

    final stop = _tourStops.elementAtOrNull(_tourStop);
    if (stop == null) return _endTour();

    final rect = _tourTargets.rectOf(stop.target);
    // A screen may name a part it does not draw. Pointing at nothing would
    // leave the reader under a scrim with no tip and no way on.
    if (rect == null) return _nextTourStop();
    if (rect != _tourRect) setState(() => _tourRect = rect);
  }

  void _nextTourStop() {
    if (_tourStop + 1 >= _tourStops.length) return _endTour();
    setState(() {
      _tourStop++;
      _tourRect = null;
    });
  }

  void _endTour() {
    final id = _tourId;
    if (id == null) return;

    setState(() {
      _tourId = null;
      _tourRect = null;
      _tourSettling = false;
    });
    unawaited(_tours?.markSeen(id));
  }

  /// The show-bar button was pressed. On the first stop that is the press it
  /// asked for, and the next part is in the bar, which has only just started
  /// sliding in.
  void _tourBarShown() {
    if (_tourStops.elementAtOrNull(_tourStop)?.target != AppHeaderPart.showBar) return;
    setState(() {
      _tourStop++;
      _tourRect = null;
      _tourSettling = true;
    });
  }

  /// The hide button was pressed. The bar's last stop is that button, which
  /// says "done" as well as "Klaar" does. Anywhere else in the bar's
  /// introduction it would leave the stops after it pointing into a bar that
  /// has gone.
  void _tourBarHidden() {
    if (_tourStops.any((stop) => stop.target == AppHeaderPart.hideBar)) _endTour();
  }

  /// The bar has arrived. Called by its slide's `onEnd`, which fires from the
  /// animation's tick or, under reduced motion, from inside a build.
  void _tourBarSettled() {
    if (_tourSettling) _afterFrame(() => setState(() => _tourSettling = false));
  }

  /// The scrim and the current stop's tip, to be laid over the whole host.
  Widget _buildTour(BuildContext context) {
    final stop = _tourStops.elementAtOrNull(_tourStop);
    final hole = _tourSettling ? null : _tourRect?.inflate(_holeMargin);

    return Positioned.fill(
      // Fades in once, when the introduction starts. A stop moving on changes
      // what is lit, not whether anything is.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: context.motion(_tourFade),
        builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
        // The page and the bar measure from the window's corner, and so does
        // this: the host fills the window from its top left.
        child: Stack(
          children: [
            Positioned.fill(child: SpotlightScrim(hole: hole)),
            if (stop != null && hole != null) _buildTip(context, stop, hole),
          ],
        ),
      ),
    );
  }

  /// Under [hole], centred on it where the window allows.
  Widget _buildTip(BuildContext context, AppTourStop stop, Rect hole) {
    final window = MediaQuery.sizeOf(context).width;
    final width = math.min(TourTip.maxWidth, window - _tipGutter * 2);
    final left = clampDouble(hole.center.dx - width / 2, _tipGutter, math.max(_tipGutter, window - _tipGutter - width));

    return Positioned(
      top: hole.bottom + _tipGap,
      left: left,
      width: width,
      child: TourTip(
        text: stop.tip,
        stop: _tourStop + 1,
        stopCount: _tourStops.length,
        beakX: clampDouble(hole.center.dx - left, _beakInset, width - _beakInset),
        // The show-bar stop is moved past by pressing the lit button itself.
        onNext: stop.target == AppHeaderPart.showBar ? null : _nextTourStop,
        onSkip: _endTour,
      ),
    );
  }

}
