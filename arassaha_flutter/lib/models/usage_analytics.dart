/// Basit Kullanım Analitiği (UX standardizasyonu turu, bölüm E).
///
/// AYRIM: Bu gerçek bir ısı haritası/oturum kaydı DEĞİLDİR — yalnızca
/// backend'deki `usage_logs` tablosunun basit bir özetidir: en çok ziyaret
/// edilen ekranlar ve en çok tıklanan butonlar.
class ScreenViewCount {
  final String screenName;
  final int viewCount;

  ScreenViewCount({required this.screenName, required this.viewCount});

  factory ScreenViewCount.fromJson(Map<String, dynamic> json) {
    return ScreenViewCount(
      screenName: json['screen_name'] as String,
      viewCount: json['view_count'] as int,
    );
  }
}

class ButtonTapCount {
  final String screenName;
  final String elementName;
  final int tapCount;

  ButtonTapCount({
    required this.screenName,
    required this.elementName,
    required this.tapCount,
  });

  factory ButtonTapCount.fromJson(Map<String, dynamic> json) {
    return ButtonTapCount(
      screenName: json['screen_name'] as String,
      elementName: json['element_name'] as String,
      tapCount: json['tap_count'] as int,
    );
  }
}

/// GET /api/analytics/summary yanıtı.
class UsageAnalyticsSummary {
  final List<ScreenViewCount> topScreens;
  final List<ButtonTapCount> topButtons;

  UsageAnalyticsSummary({required this.topScreens, required this.topButtons});

  factory UsageAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return UsageAnalyticsSummary(
      topScreens: (json['top_screens'] as List<dynamic>)
          .map((e) => ScreenViewCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      topButtons: (json['top_buttons'] as List<dynamic>)
          .map((e) => ButtonTapCount.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
