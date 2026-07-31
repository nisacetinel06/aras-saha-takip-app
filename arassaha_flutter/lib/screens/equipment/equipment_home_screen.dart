import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/equipment_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_top_bar.dart';
import 'equipment_detail_screen.dart';
import 'equipment_list_screen.dart';
import 'qr_scanner_screen.dart';

/// Ekipman / Envanter (Modül 4) — giriş ekranı. Sahadaki bir ekipmanı
/// tanımlamak için iki net yol sunar: kamera ile QR tarama, ya da (kamera
/// erişimi yoksa/istenmiyorsa veya gerçek cihazda test edilemiyorsa) manuel
/// kod girişi. Bkz. DESIGN_SYSTEM.md — Cihaz Yönetimi ile aynı desen:
/// kendi Scaffold/AppBar'ı olan, Navigator ile push edilen bağımsız bir ekran.
class EquipmentHomeScreen extends StatefulWidget {
  const EquipmentHomeScreen({super.key});

  @override
  State<EquipmentHomeScreen> createState() => _EquipmentHomeScreenState();
}

class _EquipmentHomeScreenState extends State<EquipmentHomeScreen> {
  final _codeController = TextEditingController();
  bool _isQuerying = false;
  String? _inlineError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _queryManualCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _inlineError = 'Lütfen bir ekipman kodu girin.');
      return;
    }

    setState(() {
      _isQuerying = true;
      _inlineError = null;
    });

    final provider = context.read<EquipmentProvider>();
    final equipment = await provider.fetchEquipmentByQr(code);

    if (!mounted) return;
    setState(() => _isQuerying = false);

    if (equipment != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EquipmentDetailScreen(equipmentId: equipment.id)),
      );
      return;
    }

    setState(() {
      _inlineError = provider.qrLookupErrorMessage ?? 'Bu koda ait ekipman bulunamadı.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppTopBar(title: 'Ekipman Envanteri'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner, size: 72, color: scheme.primary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Sahadaki bir direk, trafo, kesici ya da sayacı\ntanımlamak için QR kodunu okutun.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'QR Kod Tara',
                    icon: Icons.qr_code_scanner,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text('veya kod girin', style: AppTextStyles.caption(color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _queryManualCode(),
                  decoration: const InputDecoration(
                    hintText: 'Örn: TR-2024-0451',
                    prefixIcon: Icon(Icons.qr_code_2_outlined),
                    isDense: true,
                  ),
                ),
                if (_inlineError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_inlineError!, style: TextStyle(color: scheme.error, fontSize: 13), textAlign: TextAlign.center),
                ],
                const SizedBox(height: AppSpacing.sm + 4),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Sorgula',
                    icon: Icons.search,
                    variant: AppButtonVariant.secondary,
                    isLoading: _isQuerying,
                    onPressed: _queryManualCode,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Tüm Ekipmanları Listele',
                  icon: Icons.list_alt_outlined,
                  variant: AppButtonVariant.text,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EquipmentListScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
