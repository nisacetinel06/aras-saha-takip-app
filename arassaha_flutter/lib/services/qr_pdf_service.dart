import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/equipment.dart';

/// QR Kod Üretimi modülü — seçilen ekipmanlar için yazdırılabilir bir PDF
/// üretir ve işletim sisteminin paylaşım/yazdırma arayüzüyle paylaşır.
///
/// ÖNEMLİ (görsel motor tutarlılığı): ekran önizlemesi (qr_preview_screen.dart)
/// `qr_flutter`'ın `QrImageView`'ını kullanır; burada ise `pdf` paketinin
/// KENDİ `BarcodeWidget`'ı QR üretir — ikisi farklı render motoru olsa da
/// AYNI QR verisini (ekipmanın `qrCode` alanı) kodladıkları için, ikisinin de
/// ürettiği QR aynı ekipmana çözümlenir (bkz. routes/equipment.js GET
/// /qr/:qrCode — sahada bu PDF'ten kesilip yapıştırılan etiket, mobile_scanner
/// ile okutulunca birebir bu koda çözümlenmeli, bu yüzden AYRI bir "kodlama"
/// icat edilmez, ekipmanın zaten var olan qr_code'u aynen kullanılır).
///
/// ÖNEMLİ (Türkçe karakterler): pdf paketinin varsayılan (Helvetica) temel
/// fontu yalnızca Latin-1/WinAnsi kapsar — ş/ğ/ı gibi Türkçe karakterler bu
/// kodlamada YOKTUR ve sessizce yanlış/boş glif olarak basılır. Bu yüzden
/// Türkçe'yi (il/ilçe/mahalle adları, ekipman tipi etiketleri) tam kapsayan
/// bir Unicode fontu (Noto Sans, Google Fonts) açıkça yükleyip belge temasına
/// veriyoruz — uygulamanın UI tarafında zaten `google_fonts` paketiyle AYNI
/// "çalışma zamanında indir/önbelleğe al" modeli (bkz. theme/app_text_styles.dart).
class QrPdfService {
  static const _itemsPerPage = 8;

  /// PDF'i üretip paylaşım/yazdırma diyaloğunu açar. Döndürülen `bool`
  /// (`Printing.sharePdf`'in kendi sonucu) çağıran tarafın (qr_preview_screen.dart)
  /// "basıldı" işaretlemesini YALNIZCA paylaşım gerçekten tamamlandıysa
  /// tetiklemesi için kullanılır — aksi halde kullanıcı paylaşım diyaloğunu
  /// iptal etse bile ekipmanlar sessizce "basılmış" işaretlenirdi.
  static Future<bool> generateAndSharePdf(
    List<Equipment> equipmentList,
  ) async {
    if (equipmentList.isEmpty) return false;

    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    for (var i = 0; i < equipmentList.length; i += _itemsPerPage) {
      final pageItems = equipmentList.skip(i).take(_itemsPerPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.GridView(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              children: pageItems.map((eq) {
                return pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: eq.qrCode,
                      width: 120,
                      height: 120,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      '${eq.equipmentType.label} — ${eq.qrCode}',
                      style: const pw.TextStyle(fontSize: 10),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      eq.locationName,
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                );
              }).toList(),
            );
          },
        ),
      );
    }

    return Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'arassaha-qr-kodlari.pdf',
    );
  }
}
