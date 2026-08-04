import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';

/// Giriş ekranı (Modül 7 — Auth + RBAC). Sicil no + şifre ile giriş yapılır;
/// başarılı girişten sonra AuthGate (main.dart) kullanıcıyı otomatik olarak
/// MainShell'e yönlendirir — burada elle bir Navigator.push yapılmaz.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _sicilNoController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('LoginScreen');
  }

  @override
  void dispose() {
    _sicilNoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sicilNo = _sicilNoController.text.trim();
    final password = _passwordController.text;
    if (sicilNo.isEmpty || password.isEmpty) return;

    FocusScope.of(context).unfocus();
    await context.read<AuthProvider>().login(sicilNo, password);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(
                    height: 56,
                    padding: EdgeInsets.all(AppSpacing.md),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'ArasSaha',
                    style: AppTextStyles.displayLarge(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Saha Ekipleri Operasyon Uygulaması',
                    style: AppTextStyles.bodyMedium(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _sicilNoController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Sicil No',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: TextStyle(
                                color: scheme.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: 'Giriş Yap',
                      icon: Icons.login,
                      isLoading: auth.isLoading,
                      onPressed: _submit,
                    ),
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
