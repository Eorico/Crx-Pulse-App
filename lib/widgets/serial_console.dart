import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import '../services/device_log_provider.dart';
import 'motion.dart';

/// A command-prompt style view of the ESP32's serial output.
///
/// Dark panel, monospace, newest line at the bottom, auto-scrolling —
/// the shape people expect from a terminal. Lines are tinted by what
/// they are: the firmware prefixes its own output (`[Feed]`, `[Cmd]`,
/// `[Cloud]`, `[Test]`, `[Schedule]`), so the colouring is read from
/// that prefix rather than guessed.
class SerialConsole extends StatefulWidget {
  final List<DeviceLogLine> lines;
  final bool streaming;
  final String? errorMessage;

  /// Null disables the button (e.g. no device paired).
  final VoidCallback? onClear;

  final double height;

  const SerialConsole({
    super.key,
    required this.lines,
    required this.streaming,
    this.errorMessage,
    this.onClear,
    this.height = 280,
  });

  @override
  State<SerialConsole> createState() => _SerialConsoleState();
}

class _SerialConsoleState extends State<SerialConsole> {
  final _scroll = ScrollController();

  /// Auto-scroll only while the user is already at the bottom. Yanking
  /// the view down while somebody is reading back through the log is
  /// the single most irritating thing a live console can do.
  bool _pinnedToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.offset >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _pinnedToBottom) {
      setState(() => _pinnedToBottom = atBottom);
    }
  }

  @override
  void didUpdateWidget(covariant SerialConsole old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != old.lines.length && _pinnedToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  void _toBottom({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(target, duration: AppMotion.normal, curve: AppMotion.enter);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Tint from the firmware's own line prefix.
  Color _colorFor(String message) {
    if (message.startsWith('[Feed]') || message.startsWith('[Schedule]')) {
      return const Color(0xFF7EE787); // green — the machine moved
    }
    if (message.startsWith('[Test]')) {
      return const Color(0xFF79C0FF); // blue — you did that
    }
    if (message.startsWith('[Cmd]')) {
      return const Color(0xFFD2A8FF); // purple — came from the app
    }
    if (message.startsWith('[Cloud]')) {
      return const Color(0xFF8B949E); // grey — routine chatter
    }
    if (message.contains('Not Connected') ||
        message.contains('HTTP') ||
        message.contains('failed') ||
        message.contains('dropped')) {
      return const Color(0xFFFF7B72); // red — something is wrong
    }
    if (message.startsWith('=====')) {
      return const Color(0xFF6E7681); // dim — block separators
    }
    return const Color(0xFFC9D1D9); // default terminal foreground
  }

  String _stamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0D1117);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── title bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            color: const Color(0xFF161B22),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 14, color: Color(0xFF8B949E)),
                const SizedBox(width: 8),
                const Text(
                  'esp32 · serial',
                  style: TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                // Live dot — pulses while verbose output is flowing.
                PulseHalo(
                  color: AppColors.success,
                  active: widget.streaming,
                  maxRadius: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.streaming
                          ? AppColors.success
                          : const Color(0xFF6E7681),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.streaming ? 'live' : 'events only',
                  style: const TextStyle(
                    color: Color(0xFF6E7681),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                _ConsoleAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copy log',
                  onTap: widget.lines.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(
                            text: widget.lines
                                .map((l) => '${_stamp(l.at)}  ${l.message}')
                                .join('\n'),
                          ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Log copied')),
                          );
                        },
                ),
                _ConsoleAction(
                  icon: LucideIcons.trash2,
                  tooltip: 'Clear log',
                  onTap: widget.lines.isEmpty ? null : widget.onClear,
                ),
              ],
            ),
          ),

          // ── output ──
          SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                if (widget.lines.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.errorMessage ??
                            'Waiting for output from the device…\n\n'
                                'Lines appear here as the ESP32 prints them.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6E7681),
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: widget.lines.length,
                    itemBuilder: (context, i) {
                      final line = widget.lines[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${_stamp(line.at)}  ',
                              style: const TextStyle(color: Color(0xFF484F58)),
                            ),
                            TextSpan(
                              text: line.message,
                              style: TextStyle(color: _colorFor(line.message)),
                            ),
                          ]),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            height: 1.45,
                          ),
                        ),
                      );
                    },
                  ),

                // "Jump to newest" — only while scrolled back, so it is
                // not permanently in the way.
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: AnimatedOpacity(
                    opacity: _pinnedToBottom ? 0 : 1,
                    duration: AppMotion.fast,
                    child: IgnorePointer(
                      ignoring: _pinnedToBottom,
                      child: PressableScale(
                        onTap: () {
                          setState(() => _pinnedToBottom = true);
                          _toBottom();
                        },
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF21262D),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFF30363D)),
                          ),
                          child: const Row(children: [
                            Icon(LucideIcons.arrowDown,
                                size: 11, color: Color(0xFFC9D1D9)),
                            SizedBox(width: 5),
                            Text('Newest',
                                style: TextStyle(
                                    color: Color(0xFFC9D1D9),
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _ConsoleAction({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 14),
      color: const Color(0xFF8B949E),
      disabledColor: const Color(0xFF30363D),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}
