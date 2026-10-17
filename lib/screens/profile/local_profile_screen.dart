import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/sticky_header_delegate.dart';

class LocalProfileScreen extends StatefulWidget {
  const LocalProfileScreen({super.key});

  @override
  State<LocalProfileScreen> createState() => _LocalProfileScreenState();
}

class _LocalProfileScreenState extends State<LocalProfileScreen> {
  final _auth = AuthService();
  Map<String, dynamic>? _accountInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await _auth.getMyAccountInfo();
    if (mounted) setState(() { _accountInfo = info; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final dn = _accountInfo?['displayName'] as String?;
    final displayName = (dn != null && dn.isNotEmpty) ? dn : 'User';
    final email = _accountInfo?['email'] as String? ?? '';

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: StickyHeaderDelegate(
                  height: 76,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: MinimalGifHeader(title: 'Profile', subtitle: 'Your account'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                sliver: SliverList.list(children: [
              // Spinner cross-fades into the loaded card instead of
              // being replaced mid-frame.
              SwapIn(
                swapKey: _loading,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                    : Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppShadows.card),
                        child: Column(
                          children: [
                            FadeSlideIn(
                              beginScale: 0.8,
                              from: Offset.zero,
                              child: CircleAvatar(
                                radius: 36,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 28),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(displayName,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text(email,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 20),
              // Detail tiles arrive in sequence below the card.
              ...FadeSlideIn.stagger(
                [
                  _InfoTile(icon: LucideIcons.mail, label: 'Email', value: email),
                  _InfoTile(icon: LucideIcons.user, label: 'Display Name', value: displayName),
                  if (_accountInfo?['createdAt'] != null)
                    _InfoTile(
                        icon: LucideIcons.calendar,
                        label: 'Member Since',
                        value: _formatTimestamp(_accountInfo!['createdAt'])),
                ],
                initialDelay: const Duration(milliseconds: 120),
                from: const Offset(-0.05, 0.06),
              ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    try {
      // Supabase returns createdAt as an ISO-8601 string.
      final date = ts is String ? DateTime.parse(ts).toLocal() : ts as DateTime;
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return '—';
    }
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const Spacer(),
        Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }
}
