import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_top_bar.dart';

/// "Şifremi Değiştir" — bkz. routes/auth.js POST /change-password,
/// providers/auth_provider.dart changePassword.
///
/// Admin'in Kullanıcı Yönetimi panelindeki "Şifre Sıfırla" akışından
/// (mevcut şifre istemez — bir KURTARMA aracıdır, kullanıcı şifresini
/// unutmuştur) BİLİNÇLİ olarak AYRI: burada kullanıcı KENDİ isteğiyle, kendi
/// bildiği mevcut şifresini doğrulamak ZORUNDADIR. Bu doğrulama olmadan,
/// kilidi açık bırakılmış bir cihaza kısa süreliğine erişen biri kullanıcıyı
/// sessizce hesaptan atabilirdi (bkz. PROMPT "Neden Mevcut Şifre Zorunlu").
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// İstemci tarafı doğrulama — yeni şifre en az 8 karakter OLMALI VE "Yeni
  /// Şifre (Tekrar)" ile BİREBİR eşleşmeli, aksi halde istek backend'e HİÇ
  /// atılmaz (bkz. PROMPT madde 3, kabul kriteri madde 5).
  bool _validateClientSide() {
    setState(() {
      _newPasswordError = _newController.text.length < 8
          ? 'Yeni şifre en az 8 karakter olmalı.'
          : null;
      _confirmError = _confirmController.text != _newController.text
          ? 'Şifreler eşleşmiyor.'
          : null;
    });
    return _newPasswordError == null && _confirmError == null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _currentPasswordError = null);
    if (!_validateClientSide()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;

    if (!success) {
      final message =
          authProvider.changePasswordErrorMessage ?? 'Şifre değiştirilemedi.';
      // Backend 401 (mevcut şifre hatalı) döndüyse hatayı "Mevcut Şifre"
      // alanının ALTINDA göster (bkz. PROMPT madde 3); diğer hatalar (400
      // doğrulama, 429 deneme sınırı, ağ hatası vb.) genel bir SnackBar ile.
      if (authProvider.changePasswordErrorIsCurrentPasswordWrong) {
        setState(() => _currentPasswordError = message);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    await _showSuccessDialog();
    if (!mounted) return;
    // Backend bu kullanıcının TÜM refresh_token'larını (bu cihaz DAHİL)
    // zaten sunucu tarafında iptal etti (bkz. routes/auth.js) — yerel oturum
    // BURADA, kullanıcı onay mesajını GÖRDÜKTEN SONRA temizlenir; AuthGate
    // bunu dinleyip otomatik olarak LoginScreen'e düşürür (bkz. main.dart).
    await context.read<AuthProvider>().handleSessionExpired();
  }

  Future<void> _showSuccessDialog() {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.check_circle, color: scheme.primary, size: 40),
        title: const Text('Şifreniz değiştirildi'),
        content: const Text(
          'Güvenlik nedeniyle diğer cihazlardaki oturumlarınız da sonlandırıldı. '
          'Yeni şifrenizle tekrar giriş yapmanız gerekiyor.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isChangingPassword;

    return Scaffold(
      appBar: const AppTopBar(title: 'Şifremi Değiştir'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _PasswordField(
              key: const Key('current_password_field'),
              label: 'Mevcut Şifre',
              controller: _currentController,
              obscure: _obscureCurrent,
              onToggleObscure: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              errorText: _currentPasswordError,
            ),
            const SizedBox(height: AppSpacing.md),
            _PasswordField(
              key: const Key('new_password_field'),
              label: 'Yeni Şifre',
              controller: _newController,
              obscure: _obscureNew,
              onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
              errorText: _newPasswordError,
              helperText: 'En az 8 karakter',
            ),
            const SizedBox(height: AppSpacing.md),
            _PasswordField(
              key: const Key('confirm_password_field'),
              label: 'Yeni Şifre (Tekrar)',
              controller: _confirmController,
              obscure: _obscureConfirm,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              errorText: _confirmError,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Değiştir',
                icon: Icons.lock_reset_outlined,
                isLoading: isLoading,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// login_screen.dart'taki şifre alanıyla AYNI görsel dil (prefix kilit
/// ikonu, göster/gizle suffix ikonu) — tasarım sistemine tutarlılık için.
class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String? errorText;
  final String? helperText;

  const _PasswordField({
    super.key,
    required this.label,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    this.errorText,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        helperText: errorText == null ? helperText : null,
        errorText: errorText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}
