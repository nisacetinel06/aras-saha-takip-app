import 'work_order.dart' show WorkOrderPriority;

/// Modül 10 (Arıza Açıklaması Otomatik Sınıflandırma) — dört arıza tipi.
/// Python ML servisindeki (arassaha-ml) sınıflandırma etiketleriyle birebir
/// eşleşir. BUNUN work_orders tablosunda GERÇEK bir sütun karşılığı YOKTUR —
/// yalnızca kullanıcıya bir öneri göstermek ve "Uygula" dendiğinde formun
/// mevcut `title` alanına makul bir Türkçe karşılık yazmak için kullanılır
/// (bkz. create_work_order_screen.dart).
enum FaultType {
  trafoArizasi,
  direkHasari,
  kabloKopmasi,
  sayacArizasi;

  static FaultType? fromJson(String? value) {
    switch (value) {
      case 'trafo_arizasi':
        return FaultType.trafoArizasi;
      case 'direk_hasari':
        return FaultType.direkHasari;
      case 'kablo_kopmasi':
        return FaultType.kabloKopmasi;
      case 'sayac_arizasi':
        return FaultType.sayacArizasi;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case FaultType.trafoArizasi:
        return 'Trafo Arızası';
      case FaultType.direkHasari:
        return 'Direk Hasarı';
      case FaultType.kabloKopmasi:
        return 'Kablo Kopması';
      case FaultType.sayacArizasi:
        return 'Sayaç Arızası';
    }
  }
}

/// POST /api/ml/classify-description yanıtı.
///
/// DÜRÜSTLÜK NOTU: Bu öneriyi üreten model (TF-IDF + LogisticRegression),
/// Modül 9'daki RandomForestClassifier'dan (sayısal ekipman verisi) FARKLI
/// bir teknik kullanır — serbest metni sınıflandırır. Gerçek bir şirket
/// arıza kaydı metin veri seti olmadığı için sentetik/şablon tabanlı üretilmiş
/// bir veri setiyle eğitildi (bkz. arassaha-ml/README.md).
///
/// `suggestedType` null ise (metin çok kısa ya da model güveni düşükse,
/// backend bunu kasıtlı olarak böyle döner) UI HİÇBİR öneri göstermez —
/// yanlış bir öneri sunmak, hiç öneri sunmamaktan daha kötüdür.
class DescriptionClassification {
  final FaultType? suggestedType;
  final double? typeConfidence;
  final WorkOrderPriority? suggestedPriority;
  final double? priorityConfidence;

  DescriptionClassification({
    required this.suggestedType,
    required this.typeConfidence,
    required this.suggestedPriority,
    required this.priorityConfidence,
  });

  factory DescriptionClassification.fromJson(Map<String, dynamic> json) {
    return DescriptionClassification(
      suggestedType: FaultType.fromJson(json['suggested_type'] as String?),
      typeConfidence: (json['type_confidence'] as num?)?.toDouble(),
      suggestedPriority: json['suggested_priority'] != null
          ? WorkOrderPriority.fromJson(json['suggested_priority'] as String)
          : null,
      priorityConfidence: (json['priority_confidence'] as num?)?.toDouble(),
    );
  }

  bool get hasSuggestion => suggestedType != null;
}
