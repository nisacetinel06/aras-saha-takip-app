import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';

/// Login akışının 2. adımı (bkz. LoginScreen._submit) — yalnızca 2FA etkin
/// bir yönetici için görülür. AuthProvider.login()'den gelen pending_token
/// zaten AuthProvider'da tutuluyor; bu ekran yalnızca kodu toplayıp
/// AuthProvider.verifyTwoFactor()'ı çağırır. Başarılı olduğunda
/// AuthGate (main.dart) — AuthProvider'ı dinleyen kök widget — otomatik
/// olarak MainShell'e geçer; bu ekranın kendisi yalnızca kendini POP eder
/// (aksi halde MainShell, bu ekranın ALTINDA gizli kalırdı).
class TwoFactorVerifyScreen extends StatefulWidget {
  const TwoFactorVerifyScreen({super.key});

  @override
  State<TwoFactorVerifyScreen> createState() => _TwoFactorVerifyScreenState();
}

class _TwoFactorVerifyScreenState extends State<TwoFactorVerifyScreen> {
  final _codeController = TextEditingController();
  bool _showBackupCodeHint = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('TwoFactorVerifyScreen');
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    final success = await auth.verifyTwoFactor(code);

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doğrulama Kodu'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            auth.cancelTwoFactor();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.shield_outlined, size: 48, color: scheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'İki Faktörlü Doğrulama',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headingMedium(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Authenticator uygulamanızdaki 6 haneli kodu girin.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    key: const Key('two_factor_code_field'),
                    controller: _codeController,
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: AppTextStyles.headingMedium(color: scheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'Kod',
                      hintText: '123456',
                    ),
                  ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            auth.errorMessage!,
                            key: const Key('two_factor_error_message'),
                            style: TextStyle(color: scheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const Key('two_factor_submit_button'),
                    label: 'Doğrula',
                    icon: Icons.check,
                    isLoading: auth.isLoading,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => setState(() => _showBackupCodeHint = !_showBackupCodeHint),
                    child: const Text('Yedek kod mu kullanmak istiyorsunuz?'),
                  ),
                  if (_showBackupCodeHint)
                    Text(
                      'Authenticator uygulamanıza erişiminiz yoksa, 2FA '
                      'kurulumu sırasında aldığınız 8 haneli yedek kodlardan '
                      'birini yukarıdaki alana girebilirsiniz. Her yedek kod '
                      'yalnızca BİR KEZ kullanılabilir.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
