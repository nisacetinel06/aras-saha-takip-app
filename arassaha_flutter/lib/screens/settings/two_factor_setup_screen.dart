import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/two_factor_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';

enum _SetupStep { qrAndBackupCodes, enterConfirmCode, done }

/// İki Faktörlü Doğrulama (2FA) kurulum ekranı — yalnızca yönetici, Ayarlar
/// ekranından açılır. Akış: QR kod (otpauth_uri) + 8 yedek kod göster ("bu
/// kodları kaydettim" onayı olmadan devam edilemez) -> authenticator'dan
/// okunan İLK kodu doğrula (POST /2fa/confirm) -> etkinleşti.
///
/// GÜVENLİK/UX kararı: "Bu kodları güvenli bir yere kaydettim" onay kutusu
/// işaretlenmeden "Devam Et" BİLEREK pasif kalır — yedek kodlar backend'de
/// yalnızca HASH olarak saklanır (bkz. routes/twoFactor.js), bu ekrandan
/// çıkıldıktan sonra bir daha ASLA düz metin olarak gösterilemez. Bu
/// sürtünme noktası kasıtlıdır.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  _SetupStep _step = _SetupStep.qrAndBackupCodes;
  bool _codesSavedConfirmed = false;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('TwoFactorSetupScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TwoFactorProvider>().reset();
      context.read<TwoFactorProvider>().setup();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _confirmCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final provider = context.read<TwoFactorProvider>();
    final success = await provider.confirm(code);
    if (!mounted) return;

    if (success) {
      setState(() => _step = _SetupStep.done);
      // Ayarlar ekranındaki durumun (2FA etkin/değil) DERHAL güncel
      // görünmesi için — bkz. two_factor_settings_section.dart.
      context.read<UserProvider>().fetchMyProfile();
    }
  }

  void _copyAllBackupCodes(List<String> codes) {
    Clipboard.setData(ClipboardData(text: codes.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Yedek kodlar panoya kopyalandı.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TwoFactorProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'İki Faktörlü Doğrulama', showBackButton: true),
      body: Builder(
        builder: (context) {
          if (provider.isSettingUp && provider.otpauthUri == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.setupErrorMessage != null && provider.otpauthUri == null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'İki adımlı doğrulama kurulumu yüklenemedi',
              subtitle: provider.setupErrorMessage!,
              onPrimaryAction: () => context.read<TwoFactorProvider>().setup(),
              primaryActionLabel: 'Tekrar Dene',
              primaryActionVariant: AppButtonVariant.secondary,
            );
          }

          switch (_step) {
            case _SetupStep.qrAndBackupCodes:
              return _QrAndBackupCodesStep(
                otpauthUri: provider.otpauthUri!,
                backupCodes: provider.backupCodes,
                codesSavedConfirmed: _codesSavedConfirmed,
                onCodesSavedChanged: (v) => setState(() => _codesSavedConfirmed = v),
                onCopyAll: () => _copyAllBackupCodes(provider.backupCodes),
                onContinue: () => setState(() => _step = _SetupStep.enterConfirmCode),
              );
            case _SetupStep.enterConfirmCode:
              return _EnterConfirmCodeStep(
                controller: _codeController,
                isConfirming: provider.isConfirming,
                errorMessage: provider.confirmErrorMessage,
                onConfirm: _confirmCode,
              );
            case _SetupStep.done:
              return _DoneStep(onFinish: () => Navigator.of(context).pop());
          }
        },
      ),
    );
  }
}

class _QrAndBackupCodesStep extends StatelessWidget {
  final String otpauthUri;
  final List<String> backupCodes;
  final bool codesSavedConfirmed;
  final ValueChanged<bool> onCodesSavedChanged;
  final VoidCallback onCopyAll;
  final VoidCallback onContinue;

  const _QrAndBackupCodesStep({
    required this.otpauthUri,
    required this.backupCodes,
    required this.codesSavedConfirmed,
    required this.onCodesSavedChanged,
    required this.onCopyAll,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          '1. QR Kodu Okutun',
          style: AppTextStyles.headingMedium(color: scheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Google Authenticator, Microsoft Authenticator veya Authy '
          'uygulamasıyla bu QR kodu okutun.',
          style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              color: Colors.white,
              child: QrImageView(
                data: otpauthUri,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          '2. Yedek Kodlarınızı Kaydedin',
          style: AppTextStyles.headingMedium(color: scheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Telefonunuza erişemediğinizde giriş yapabilmeniz için bu 8 kodu '
          'güvenli bir yere kaydedin. Her kod yalnızca BİR KEZ kullanılabilir '
          've bu kodları BİR DAHA ASLA göremeyeceksiniz.',
          style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 3.2,
                children: backupCodes
                    .map(
                      (code) => Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: SelectableText(
                          code,
                          style: AppTextStyles.dataMono(color: scheme.onSurface),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              AppButton(
                label: 'Tümünü Kopyala',
                icon: Icons.copy_all_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: onCopyAll,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          value: codesSavedConfirmed,
          onChanged: (v) => onCodesSavedChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Bu kodları güvenli bir yere kaydettim.'),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Devam Et',
          icon: Icons.arrow_forward,
          onPressed: codesSavedConfirmed ? onContinue : null,
        ),
      ],
    );
  }
}

class _EnterConfirmCodeStep extends StatelessWidget {
  final TextEditingController controller;
  final bool isConfirming;
  final String? errorMessage;
  final VoidCallback onConfirm;

  const _EnterConfirmCodeStep({
    required this.controller,
    required this.isConfirming,
    required this.errorMessage,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          '3. Kodu Doğrulayın',
          style: AppTextStyles.headingMedium(color: scheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Authenticator uygulamanızda şu an görünen 6 haneli kodu girin.',
          style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofocus: true,
          onSubmitted: (_) => onConfirm(),
          style: AppTextStyles.headingMedium(color: scheme.onSurface),
          decoration: const InputDecoration(labelText: 'Kod', hintText: '123456'),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(errorMessage!, style: TextStyle(color: scheme.error, fontSize: 13)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Onayla ve Etkinleştir',
          icon: Icons.check,
          isLoading: isConfirming,
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  final VoidCallback onFinish;
  const _DoneStep({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: AppColors.success(context)),
            const SizedBox(height: AppSpacing.md),
            Text(
              '2FA Etkinleştirildi',
              style: AppTextStyles.headingMedium(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Bundan sonra girişte şifrenize ek olarak authenticator '
              'kodunuz da istenecek.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: AppButton(label: 'Tamam', onPressed: onFinish),
            ),
          ],
        ),
      ),
    );
  }
}
