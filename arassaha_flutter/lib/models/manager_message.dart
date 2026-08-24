/// Yöneticiden Çalışana Duyuru/Mesaj Sistemi.
///
/// TEK YÖNLÜ yayın: yalnızca yönetici mesaj oluşturup bir/birden çok
/// çalışana gönderir; çalışan SADECE okur, cevap YAZAMAZ. Bu yüzden AI
/// Asistan'daki (chat_message.dart) gibi bir "sohbet" modeli DEĞİL —
/// backend'de de conversations/messages değil, basitleştirilmiş
/// manager_messages/manager_message_recipients tabloları kullanılıyor (bkz.
/// database.js).
library;

/// Çalışan görünümü: GET /api/manager-messages yanıtındaki tek bir satır —
/// mesajın tam içeriğini VE bu kullanıcı için okunma durumunu taşır (ayrı
/// bir detay isteği gerekmez, liste zaten tam içeriği döner).
class ManagerMessage {
  final int id;
  final String? title;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;
  final String senderName;
  final String senderRole;

  ManagerMessage({
    required this.id,
    this.title,
    required this.content,
    required this.createdAt,
    this.readAt,
    required this.senderName,
    required this.senderRole,
  });

  bool get isRead => readAt != null;

  factory ManagerMessage.fromJson(Map<String, dynamic> json) {
    return ManagerMessage(
      id: json['id'] as int,
      title: json['title'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      senderName: json['sender_name'] as String,
      senderRole: json['sender_role'] as String? ?? '',
    );
  }

  ManagerMessage copyWith({DateTime? readAt}) {
    return ManagerMessage(
      id: id,
      title: title,
      content: content,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      senderName: senderName,
      senderRole: senderRole,
    );
  }
}

/// Yönetici görünümü: GET /api/manager-messages/sent yanıtındaki tek bir
/// satır — "12 kişiden 8'i okudu" özetini üretmek için gereken sayaçları taşır.
class SentManagerMessage {
  final int id;
  final String? title;
  final String content;
  final DateTime createdAt;
  final int recipientCount;
  final int readCount;

  SentManagerMessage({
    required this.id,
    this.title,
    required this.content,
    required this.createdAt,
    required this.recipientCount,
    required this.readCount,
  });

  factory SentManagerMessage.fromJson(Map<String, dynamic> json) {
    return SentManagerMessage(
      id: json['id'] as int,
      title: json['title'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      recipientCount: json['recipient_count'] as int,
      readCount: json['read_count'] as int,
    );
  }
}

/// GET /api/manager-messages/:id/read-status yanıtındaki tek bir alıcı satırı
/// — hangi çalışanın okuyup hangisinin okumadığını (ve ne zaman okuduğunu) taşır.
class MessageRecipientStatus {
  final int recipientUserId;
  final String name;
  final String role;
  final DateTime? readAt;

  MessageRecipientStatus({
    required this.recipientUserId,
    required this.name,
    required this.role,
    this.readAt,
  });

  bool get isRead => readAt != null;

  factory MessageRecipientStatus.fromJson(Map<String, dynamic> json) {
    return MessageRecipientStatus(
      recipientUserId: json['recipient_user_id'] as int,
      name: json['name'] as String,
      role: json['role'] as String? ?? '',
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
    );
  }
}

/// GET /api/manager-messages/:id/read-status'un TAMAMI — mesaj gövdesi + tüm
/// alıcıların okundu durumu, bkz. SentMessageReadStatusScreen.
class MessageReadStatus {
  final int id;
  final String? title;
  final String content;
  final DateTime createdAt;
  final List<MessageRecipientStatus> recipients;

  MessageReadStatus({
    required this.id,
    this.title,
    required this.content,
    required this.createdAt,
    required this.recipients,
  });

  int get readCount => recipients.where((r) => r.isRead).length;

  factory MessageReadStatus.fromJson(Map<String, dynamic> json) {
    return MessageReadStatus(
      id: json['id'] as int,
      title: json['title'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      recipients: (json['recipients'] as List)
          .map(
            (r) => MessageRecipientStatus.fromJson(r as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
