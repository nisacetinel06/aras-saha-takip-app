import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/equipment.dart';
import '../../providers/qr_generation_provider.dart';
import '../../services/qr_pdf_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/sticky_form_footer.dart';

/// QR Kod Üretimi — seçilen ekipmanların QR önizlemesi ve PDF oluşturma
/// ekranı. Buradaki `QrImageView` (qr_flutter) yalnızca EKRAN önizlemesidir;
/// gerçek yazdırılabilir çıktı `QrPdfService`'in `pdf` paketiyle ürettiği
/// PDF'tir — ikisi farklı render motoru olsa da AYNI `equipment.qrCode`
/// verisini kodlar (bkz. qr_pdf_service.dart dosya başı notu).
class QrPreviewScreen extends StatefulWidget {
  final List<Equipment> equipmentList;
  const QrPreviewScreen({super.key, required this.equipmentList});

  @override
  State<QrPreviewScreen> createState() => _QrPreviewScreenState();
}

class _QrPreviewScreenState extends State<QrPreviewScreen> {
  bool _isGenerating = false;

  Future<void> _generateAndSave() async {
    setState(() => _isGenerating = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ids = widget.equipmentList.map((e) => e.id).toList();
    final count = widget.equipmentList.length;

    bool shared;
    try {
      shared = await QrPdfService.generateAndSharePdf(widget.equipmentList);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('PDF oluşturulurken bir hata oluştu. Tekrar deneyin.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    // Paylaşım diyaloğu iptal edildiyse (shared=false) "basıldı" işareti
    // GÖNDERİLMEZ — aksi halde kullanıcı paylaşımı iptal etse bile
    // ekipmanlar sessizce "etiketi basılmış" sayılırdı (bkz.
    // qr_pdf_service.dart dosya başı notu).
    if (!shared) {
      setState(() => _isGenerating = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'PDF paylaşımı tamamlanmadı, ekipmanlar işaretlenmedi.',
          ),
        ),
      );
      return;
    }

    final provider = context.read<QrGenerationProvider>();
    final success = await provider.markAsPrinted(ids);
    if (!mounted) return;
    setState(() => _isGenerating = false);

    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$count ekipman için QR kodu oluşturuldu ve işaretlendi.',
          ),
        ),
      );
      // Seçim ekranına dön — provider zaten refetch etti, orada liste
      // otomatik güncel (basılan ekipmanlar düşmüş) görünecek.
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.markPrintedErrorMessage ??
                'QR kodları basıldı olarak işaretlenemedi.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppTopBar(title: 'QR Önizleme'),
      body: SafeArea(
        top: false,
        child: GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.78,
          ),
          itemCount: widget.equipmentList.length,
          itemBuilder: (context, index) {
            final equipment = widget.equipmentList[index];
            return AppCard(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // QR kodlar HER ZAMAN beyaz zemin üzerinde — koyu temada
                  // bile taranabilirlik için (bkz. two_factor_setup_screen.dart
                  // AYNI desen, QrImageView zaten arka planı VARSAYILAN
                  // OLARAK beyaz basmaz, açıkça verilmesi gerekir).
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    color: Colors.white,
                    child: QrImageView(
                      data: equipment.qrCode,
                      size: 96,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    '${equipment.equipmentType.label} — ${equipment.qrCode}',
                    style: AppTextStyles.bodyMedium(
                      color: scheme.onSurface,
                    ).copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    equipment.locationName,
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: StickyFormFooter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'PDF Olarak Kaydet/Paylaş',
                icon: Icons.picture_as_pdf_outlined,
                isLoading: _isGenerating,
                onPressed: _isGenerating ? null : _generateAndSave,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Geri',
                variant: AppButtonVariant.secondary,
                onPressed: _isGenerating
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
