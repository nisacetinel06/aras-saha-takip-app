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

  ChatMessage({
    required this.id,
    required this.role,
    required this.message,
    required this.createdAt,
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
