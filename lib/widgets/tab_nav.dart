import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import 'motion.dart';

/// Bottom tab bar — a solid dark-green docked bar whose tabs sit in a
/// horizontally scrollable strip (swipe the bar to reach more tabs).
/// Both edges carry a soft "ghost" fade so partially-scrolled icons
/// dissolve into the bar. The ACTIVE tab lifts its icon, lights it with
/// a soft glow, and reveals its label; inactive tabs are plain muted
/// icons. The strip auto-scrolls to keep the active tab centred, and it
/// can never overflow its width.
///
/// LAYOUT RULES — the active icon used to look sliced, for two reasons,
/// and both are structural rather than cosmetic:
///
///  1. A hard-edged "pill" sat behind the tab, centred in the strip,
///     while the selected icon was translated 8px ABOVE it. The icon
///     crossed the pill's top edge, and that edge read as a cut line
///     straight through it. The highlight is now a soft circular glow
///     with no edge for the icon to cross.
///
///  2. The icon was moved with a transform, which paints outside the
///     widget's own box without making it any bigger. With the strip
///     exactly as tall as an unselected tab — and `easeOutBack`
///     overshooting past the target — the raised icon ended up above
///     the scroll viewport's top edge, which clips hard.
///
/// So: every tab is a fixed [_stripHeight] box with FIXED zones for the
/// icon and the label, and the lift is produced by a spacer BELOW the
/// content rather than by painting above the box. Nothing can land
/// outside the viewport no matter how far a curve overshoots.
class TabNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const TabNav({super.key, required this.currentIndex, required this.onTap});

  static const items = [
    (icon: LucideIcons.layoutGrid, label: 'Dashboard'),
    (icon: LucideIcons.slidersHorizontal, label: 'Manage'),
    (icon: LucideIcons.barChart3, label: 'Analytics'),
    (icon: LucideIcons.wifi, label: 'Setup'),
    (icon: LucideIcons.bell, label: 'Alerts'),
    (icon: LucideIcons.user, label: 'Profile'),
    (icon: LucideIcons.settings, label: 'Settings'),
  ];

  /// Fixed width of one tab slot.
  static const double slotWidth = 72;

  /// Height of the scrollable strip. Must be at least
  /// [_iconZone] + [_labelZone] + [_liftSpacer].
  static const double _stripHeight = 62;

  /// Reserved height for the icon. Fits the selected 26px icon even
  /// when the spring curve overshoots its scale.
  static const double _iconZone = 32;

  /// Reserved height for the label. Always reserved, selected or not,
  /// so revealing the label cannot shift the icon.
  static const double _labelZone = 14;

  /// Added below the content when selected. A Column centres its
  /// children, so N px of spacer at the bottom lifts the icon and label
  /// by N/2 — all of it inside the box.
  static const double _liftSpacer = 12;

  @override
  State<TabNav> createState() => _TabNavState();
}

class _TabNavState extends State<TabNav> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(TabNav.items.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bringActiveIntoView());
  }

  @override
  void didUpdateWidget(covariant TabNav old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bringActiveIntoView());
    }
  }

  void _bringActiveIntoView() {
    final ctx = _keys[widget.currentIndex].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: AppMotion.normal,
      curve: AppMotion.enter,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(color: Color(0x33000000), offset: Offset(0, -4), blurRadius: 18)
        ],
      ),
      child: SizedBox(
        height: TabNav._stripHeight,
        child: ShaderMask(
          // Ghost fade on both edges: tabs dissolve into the bar as they
          // scroll past the left/right edge.
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.07, 0.93, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            // No Stack / no travelling pill: each tab now carries its
            // own soft glow, which cross-fades in place. There is no
            // hard edge that can slice across an icon.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (int i = 0; i < TabNav.items.length; i++)
                  _TabItem(
                    key: _keys[i],
                    icon: TabNav.items[i].icon,
                    label: TabNav.items[i].label,
                    selected: i == widget.currentIndex,
                    onTap: () {
                      if (i != widget.currentIndex) HapticFeedback.selectionClick();
                      widget.onTap(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: TabNav.slotWidth,
        // Fixed height: the tab owns this whole box, so the content can
        // move within it without ever reaching the viewport's edge.
        height: TabNav._stripHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ICON — fixed zone, so a larger selected icon (and the
            // spring's scale overshoot) changes nothing about layout.
            SizedBox(
              height: TabNav._iconZone,
              child: Center(
                child: AnimatedScale(
                  scale: selected ? 1.0 : 0.86,
                  duration: AppMotion.normal,
                  curve: AppMotion.spring,
                  // Soft radial highlight instead of a bordered pill.
                  // Two things matter here: it has no hard edge to cut
                  // across the icon, and it is sized to the icon zone
                  // and already transparent at its own rim — so unlike
                  // an outward BoxShadow glow, it cannot spill past the
                  // strip and be clipped into a straight line.
                  child: AnimatedContainer(
                    duration: AppMotion.normal,
                    curve: AppMotion.smooth,
                    width: TabNav._iconZone,
                    height: TabNav._iconZone,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: selected ? 0.20 : 0.0),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: Icon(
                        icon,
                        key: ValueKey(selected),
                        size: selected ? 26 : 22,
                        color:
                            selected ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // LABEL — zone always reserved; only its opacity changes,
            // so showing it never nudges the icon.
            SizedBox(
              height: TabNav._labelZone,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: AppMotion.fast,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),

            // LIFT — a spacer below the content. Because the Column is
            // centred, growing this raises the icon and label by half
            // its height, entirely inside the box. This replaces the
            // old Matrix4 translation, which painted outside the box
            // and so got clipped by the scroll viewport.
            AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.enter,
              height: selected ? TabNav._liftSpacer : 0,
            ),
          ],
        ),
      ),
    );
  }
}
