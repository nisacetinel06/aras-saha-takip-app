/// Yalnızca İSTEMCİ tarafında tutulan, iyimser (optimistic) gönderim
/// durumu — backend'in `chat_messages` tablosunda böyle bir alan YOK,
/// `fromJson`'dan gelen (geçmiş/asistan yanıtı) her mesaj zaten sunucuda
/// kalıcı olduğu için doğrudan [gonderildi] varsayar. Yalnızca
/// [AssistantProvider.sendMessage]'ın iyimser eklediği kullanıcı
/// baloncuğu, gerçek sonuç (başarı/hata) belli olana kadar [gonderiliyor]
/// ile başlar.
enum ChatMessageStatus { gonderildi, gonderiliyor, basarisiz }

/// AI Asistan / Sohbet Arayüzü (Modül 16).
///
/// Hem GET /api/assistant/history hem de POST /api/assistant/query'nin
/// `reply` alanı AYNI şekli (chat_messages satırı) döner — bu yüzden tek bir
/// model her iki uçtan da fromJson ile üretilebilir.
class ChatMessage {
  final int id;
  final String role; // 'user' | 'assistant'
  final String message;
  final DateTime createdAt;
  final ChatMessageStatus status;

  ChatMessage({
    required this.id,
    required this.role,
    required this.message,
    required this.createdAt,
    this.status = ChatMessageStatus.gonderildi,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      role: json['role'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// [retryMessage]'ın aynı mesajı, yalnızca `status` değişmiş olarak
  /// LİSTEDEKİ YERİNDE güncelleyebilmesi için — model immutable kalır,
  /// provider `_messages[index] = eski.copyWith(...)` yapar.
  ChatMessage copyWith({ChatMessageStatus? status}) {
    return ChatMessage(
      id: id,
      role: role,
      message: message,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }
}

/// POST /api/assistant/query yanıtının tamamı — asistanın metin cevabı
/// (`message`) ve varsa (intent='navigate_to_screen' ise) uygulama içi
/// yönlendirme talebi (`action`, bkz. routes/assistant.js). `navigateScreen`
/// null ise bu sıradan bir metin yanıtıdır, ekran hiçbir şey yapmaz.
class AssistantReply {
  final ChatMessage message;
  final String? navigateScreen;
  final String? navigateStatus;

  AssistantReply({
    required this.message,
    this.navigateScreen,
    this.navigateStatus,
  });

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as Map<String, dynamic>?;
    return AssistantReply(
      message: ChatMessage.fromJson(json['reply'] as Map<String, dynamic>),
      navigateScreen: action != null && action['type'] == 'navigate'
          ? action['screen'] as String?
          : null,
      navigateStatus: action?['status'] as String?,
    );
  }
}
