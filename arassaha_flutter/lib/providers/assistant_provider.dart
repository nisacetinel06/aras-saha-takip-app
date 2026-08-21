import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../utils/error_mapper.dart';

/// AI Asistan / Sohbet Arayüzü (Modül 16) ekranının state'i.
///
/// Kullanıcı mesajı gönderildiğinde ÖNCE `messages` listesine iyimser
/// (optimistic) olarak eklenir (backend'in cevabını beklemeden anında
/// görünür), ardından `isTyping = true` olur ve backend'den asistan yanıtı
/// gelince listeye eklenir. Backend'e ulaşılamazsa (network hatası) kullanıcı
/// mesajı listede KALIR ama `status`ü `basarisiz`e döner (bkz.
/// [ChatMessageStatus], [retryMessage]) — Gemini API'nin kendisi
/// ulaşılamazsa (backend tarafında yakalanan durum) zaten backend 200 ile
/// zarif bir "şu an yanıt veremiyorum" mesajı döner (bkz. routes/assistant.js),
/// bu yüzden burada ayrıca bir "asistan offline" dalı yok.
class AssistantProvider extends ChangeNotifier {
  final ApiService _apiService;

  AssistantProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  final List<ChatMessage> _messages = [];
  bool _isLoadingHistory = false;
  String? _historyErrorMessage;
  bool _isTyping = false;
  String? _sendErrorMessage;

  List<ChatMessage> get messages => _messages;
  bool get isLoadingHistory => _isLoadingHistory;
  String? get historyErrorMessage => _historyErrorMessage;
  bool get isTyping => _isTyping;
  String? get sendErrorMessage => _sendErrorMessage;

  Future<void> fetchHistory() async {
    _isLoadingHistory = true;
    _historyErrorMessage = null;
    notifyListeners();

    try {
      final history = await _apiService.getAssistantHistory();
      _messages
        ..clear()
        ..addAll(history);
    } catch (e) {
      _historyErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  /// Dönüş değeri, backend'in ürettiği bir uygulama-içi yönlendirme talebi
  /// varsa ekrana (assistant_chat_screen.dart) bunu iletir — örn. kullanıcı
  /// "beni iş emirlerine götür" derse `screen: 'is_emirleri'` döner. Sıradan
  /// bir metin yanıtında null döner, ekran hiçbir şey yapmaz.
  ///
  /// Gönderim başarısız olursa kullanıcı baloncuğu listeden SİLİNMEZ — id'si
  /// artık (negatif, çakışmayan bir zaman damgası) [retryMessage]'ın hangi
  /// baloncuğu yeniden göndereceğini bulabilmesi için KALICI bir referans
  /// görevi görür; yalnızca `status` `basarisiz`e döner (bkz.
  /// _MessageBubble — kırmızı "Gönderilemedi, tekrar dene" işareti).
  Future<({String screen, String? status})?> sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    final localId = -DateTime.now().millisecondsSinceEpoch;
    _messages.add(
      ChatMessage(
        id: localId,
        role: 'user',
        message: trimmed,
        createdAt: DateTime.now(),
        status: ChatMessageStatus.gonderiliyor,
      ),
    );
    _isTyping = true;
    _sendErrorMessage = null;
    notifyListeners();

    try {
      final reply = await _apiService.sendAssistantMessage(trimmed);
      _setMessageStatus(localId, ChatMessageStatus.gonderildi);
      _messages.add(reply.message);
      if (reply.navigateScreen != null) {
        return (screen: reply.navigateScreen!, status: reply.navigateStatus);
      }
      return null;
    } catch (e) {
      _setMessageStatus(localId, ChatMessageStatus.basarisiz);
      _sendErrorMessage = mapExceptionToUserMessage(e);
      return null;
    } finally {
      _isTyping = false;
      notifyListeners();
    }
  }

  /// Yalnızca `basarisiz` durumundaki TEK bir baloncuğu, AYNI içerikle
  /// tekrar gönderir — [sendMessage]'ın aksine sohbetin tamamını yeniden
  /// YÜKLEMEZ, yalnızca bu tek mesajı yeniden dener (bkz. PROMPT madde 3).
  /// `messageId`, [ChatMessage.id] ile AYNI tip (int) — sunucudan gelen
  /// gerçek kayıtlar da iyimser eklenen yerel baloncuklar da bu alanı zaten
  /// int olarak taşıyor, ayrıca bir String'e çevirmeye gerek yok.
  Future<void> retryMessage(int messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final target = _messages[index];
    if (target.status != ChatMessageStatus.basarisiz) return;

    _messages[index] = target.copyWith(status: ChatMessageStatus.gonderiliyor);
    _sendErrorMessage = null;
    notifyListeners();

    try {
      final reply = await _apiService.sendAssistantMessage(target.message);
      _setMessageStatus(messageId, ChatMessageStatus.gonderildi);
      _messages.add(reply.message);
    } catch (e) {
      _setMessageStatus(messageId, ChatMessageStatus.basarisiz);
      _sendErrorMessage = mapExceptionToUserMessage(e);
    } finally {
      notifyListeners();
    }
  }

  void _setMessageStatus(int messageId, ChatMessageStatus status) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(status: status);
  }
}
