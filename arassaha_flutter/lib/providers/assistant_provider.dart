import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

/// AI Asistan / Sohbet Arayüzü (Modül 16) ekranının state'i.
///
/// Kullanıcı mesajı gönderildiğinde ÖNCE `messages` listesine iyimser
/// (optimistic) olarak eklenir (backend'in cevabını beklemeden anında
/// görünür), ardından `isTyping = true` olur ve backend'den asistan yanıtı
/// gelince listeye eklenir. Backend'e ulaşılamazsa (network hatası) kullanıcı
/// mesajı listede KALIR ama bir hata mesajı ayrıca gösterilir — Gemini
/// API'nin kendisi ulaşılamazsa (backend tarafında yakalanan durum) zaten
/// backend 200 ile zarif bir "şu an yanıt veremiyorum" mesajı döner (bkz.
/// routes/assistant.js), bu yüzden burada ayrıca bir "asistan offline" dalı
/// yok.
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
      _historyErrorMessage = e.toString();
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  /// Dönüş değeri, backend'in ürettiği bir uygulama-içi yönlendirme talebi
  /// varsa ekrana (assistant_chat_screen.dart) bunu iletir — örn. kullanıcı
  /// "beni iş emirlerine götür" derse `screen: 'is_emirleri'` döner. Sıradan
  /// bir metin yanıtında null döner, ekran hiçbir şey yapmaz.
  Future<({String screen, String? status})?> sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    // İyimser ekleme: geçici (negatif, çakışmayan) bir id ile kullanıcı
    // baloncuğu anında görünür. Sunucudaki gerçek kayıt farklı bir id
    // taşıyacaktır ama bu ekranda id eşleştirmesi hiçbir yerde kullanılmaz
    // (yalnızca listede sırayla gösterilir), bu yüzden zararsızdır.
    _messages.add(
      ChatMessage(
        id: -DateTime.now().millisecondsSinceEpoch,
        role: 'user',
        message: trimmed,
        createdAt: DateTime.now(),
      ),
    );
    _isTyping = true;
    _sendErrorMessage = null;
    notifyListeners();

    try {
      final reply = await _apiService.sendAssistantMessage(trimmed);
      _messages.add(reply.message);
      if (reply.navigateScreen != null) {
        return (screen: reply.navigateScreen!, status: reply.navigateStatus);
      }
      return null;
    } catch (e) {
      _sendErrorMessage = e.toString();
      return null;
    } finally {
      _isTyping = false;
      notifyListeners();
    }
  }
}
