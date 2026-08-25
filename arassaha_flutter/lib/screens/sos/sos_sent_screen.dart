import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/sos_alert.dart';
import '../../providers/sos_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/emergency_contact.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

/// Acil Durum (SOS) Modülü — Gönderim Sonrası Ekran.
///
/// "Ara" butonu BİLİNÇLİ olarak bildirim gönderme akışıyla EŞİT görsel
/// ağırlıkta: bu bir ikincil/küçük seçenek DEĞİL, uygulama içi bildirime
/// güvenmek yerine (ağ hatası, dispeçerin telefonuna bakmaması vb.
/// senaryolarda) gerçek bir acil durumda BİRİNCİL güvenilir yöntem olabilir.
/// Not alanı ise TAM TERSİNE bilinçli olarak KÜÇÜK/opsiyonel — kullanıcı bu
/// ekranı hiç doldurmadan da çıkabilmeli (bkz. Genel Kurallar).
class SosSentScreen extends StatefulWidget {
  final int alertId;
  const SosSentScreen({super.key, required this.alertId});

  @override
  State<SosSentScreen> createState() => _SosSentScreenState();
}

class _SosSentScreenState extends State<SosSentScreen> {
  final _noteController = TextEditingController();

  SupervisorContact? _supervisor;
  bool _isLoadingSupervisor = true;

  bool _isSendingNote = false;
  bool _noteSent = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SosSentScreen');
    _loadSupervisorContact();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadSupervisorContact() async {
    try {
      final contact = await ApiService().getMySupervisorContact();
      if (!mounted) return;
      setState(() => _supervisor = contact);
    } catch (_) {
      // Sessizce yutulur — bulunamasa bile aşağıdaki "Ara" butonu sabit Acil
      // Durum Hattı'na (bkz. utils/emergency_contact.dart) düşerek çalışmaya
      // devam eder, kullanıcı asla butonsuz kalmaz.
    } finally {
      if (mounted) setState(() => _isLoadingSupervisor = false);
    }
  }

  String get _callNumber =>
      (_supervisor?.phone != null && _supervisor!.phone!.trim().isNotEmpty)
      ? _supervisor!.phone!.trim()
      : emergencyHotlineNumber;

  String get _callLabel =>
      (_supervisor?.phone != null && _supervisor!.phone!.trim().isNotEmpty)
      ? '${_supervisor!.name} — Yöneticimi Ara'
      : emergencyHotlineLabel;

  Future<void> _call() async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse('tel:$_callNumber');
    try {
      final opened = await launchUrl(uri);
      if (!opened && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Arama uygulaması açılamadı.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Arama uygulaması açılamadı.')),
      );
    }
  }

  Future<void> _sendNote() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) return;

    setState(() => _isSendingNote = true);
    final success = await context.read<SosProvider>().addNote(
      widget.alertId,
      note,
    );
    if (!mounted) return;
    setState(() {
      _isSendingNote = false;
      _noteSent = success;
    });
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not eklenemedi, lütfen tekrar deneyin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = AppColors.danger(context);
    final onDanger = accessibleOnColor(danger);
    final success = AppColors.success(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acil Durum Bildirimi'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AppCard(
              statusStripeColor: success,
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: success, size: 32),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Text(
                      'Bildiriminiz gönderildi, konumunuz dispeçer/yöneticinize iletiliyor.',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // "Ara" — bildirim gönderme akışıyla EŞİT görsel ağırlıkta, dolu/
            // kırmızı, büyük bir buton (bkz. sınıf dokümantasyonu).
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: danger,
                  foregroundColor: onDanger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                onPressed: _isLoadingSupervisor ? null : _call,
                icon: const Icon(Icons.call, size: 26),
                label: Text(
                  _isLoadingSupervisor ? 'Yükleniyor...' : _callLabel,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              'Not Ekle (opsiyonel)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ne oldu, neye ihtiyacınız var? Bu adımı atlayıp doğrudan çıkabilirsiniz.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    enabled: !_noteSent,
                    decoration: const InputDecoration(
                      hintText: 'Örn. Yaralanma var, ambulans gerekiyor...',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      label: _noteSent ? 'Not Gönderildi' : 'Notu Gönder',
                      icon: _noteSent ? Icons.check : Icons.send_outlined,
                      variant: AppButtonVariant.secondary,
                      isLoading: _isSendingNote,
                      onPressed: _noteSent ? null : _sendNote,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            AppButton(
              label: 'Ana Sayfaya Dön',
              variant: AppButtonVariant.text,
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}
