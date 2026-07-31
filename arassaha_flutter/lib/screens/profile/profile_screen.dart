import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/user_avatar.dart';
import '../admin/user_management_list_screen.dart';

/// Profil ekranı (Modül 8) — YALNIZCA GÖRÜNTÜLEME. Kullanıcı kendi özlük
/// bilgilerini (fotoğraf, telefon, e-posta) burada DÜZENLEYEMEZ; bu bilgiler
/// yalnızca yönetici, Kullanıcı Yönetimi panelinden değiştirir (bkz.
/// user_management_list_screen.dart, user_edit_screen.dart) — gerçek
/// kurumsal sistemlerdeki İK/yönetim modeliyle aynı yaklaşım.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().fetchMyProfile();
    });
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Çıkış Yap', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userProvider = context.watch<UserProvider>();
    final scheme = Theme.of(context).colorScheme;

    final profile = userProvider.myProfile;

    if (userProvider.isLoadingProfile && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (userProvider.profileErrorMessage != null && profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 56, color: scheme.error),
              const SizedBox(height: AppSpacing.sm + 4),
              Text(userProvider.profileErrorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Tekrar Dene',
                onPressed: () => context.read<UserProvider>().fetchMyProfile(),
              ),
            ],
          ),
        ),
      );
    }

    if (profile == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () => context.read<UserProvider>().fetchMyProfile(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xl),
        children: [
          Center(
            child: Column(
              children: [
                UserAvatar(photoPath: profile.photoPath, initials: profile.initials, role: profile.role, radius: 48),
                const SizedBox(height: AppSpacing.md),
                Text(profile.name, style: AppTextStyles.displayLarge(color: scheme.onSurface)),
                const SizedBox(height: AppSpacing.sm),
                RoleBadge(role: profile.role, label: auth.roleLabel),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _InfoRow(icon: Icons.badge_outlined, label: 'Sicil No', value: profile.sicilNo),
                const Divider(height: 1),
                _InfoRow(icon: Icons.phone_outlined, label: 'Telefon', value: profile.phone),
                const Divider(height: 1),
                _InfoRow(icon: Icons.email_outlined, label: 'E-posta', value: profile.email),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (auth.isYonetici) ...[
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Kullanıcı Yönetimi Paneline Git',
                icon: Icons.manage_accounts_outlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserManagementListScreen()),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Çıkış Yap',
              icon: Icons.logout_outlined,
              variant: AppButtonVariant.destructive,
              onPressed: () => _confirmLogout(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _InfoRow({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  hasValue ? value! : 'Belirtilmemiş',
                  style: AppTextStyles.bodyMedium(
                    color: hasValue ? scheme.onSurface : scheme.onSurfaceVariant,
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
