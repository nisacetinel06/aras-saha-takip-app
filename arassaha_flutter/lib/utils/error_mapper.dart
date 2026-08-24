import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:geolocator/geolocator.dart'
    show LocationServiceDisabledException, PermissionDeniedException;
import 'package:mobile_scanner/mobile_scanner.dart'
    show MobileScannerException, MobileScannerErrorCode;

import '../services/api_service.dart';

/// Yakalanan HERHANGİ bir hatayı (ağ, sunucu, ayrıştırma) kullanıcıya
/// gösterilecek, Türkçe, kısa ve mümkünse aksiyon önerici bir mesaja çevirir.
///
/// TÜM provider'ların catch bloklarının TEK ortak çıkış noktası — daha önce
/// her provider kendi `e.toString()`'ini `errorMessage` olarak kullanıyordu,
/// bu da kullanıcıya `SocketException: Failed host lookup: ...` gibi ham,
/// teknik metinler gösteriyordu (bkz. proje geçmişi/Adım 0 taraması).
///
/// Saf bir fonksiyondur (girdi alır, string döner, yan etkisi yoktur) —
/// `kDebugMode` altındaki `developer.log` çağrısı istisnadır: yalnızca
/// GELİŞTİRİCİ konsoluna yazar, dönüş değerini ETKİLEMEZ ve release
/// build'de HİÇ çalışmaz (bkz. madde 5 — teknik detay release'de asla
/// kullanıcıya/konsola sızmamalı).
String mapExceptionToUserMessage(dynamic error) {
  if (kDebugMode) {
    developer.log(
      'Yakalanan hata: $error',
      name: 'ArasSahaError',
      error: error,
    );
  }

  if (error is SocketException) {
    return 'İnternet bağlantınızı kontrol edin';
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermiyor, lütfen tekrar deneyin';
  }
  if (error is FormatException) {
    return 'Beklenmeyen bir hata oluştu';
  }
  if (error is LocationServiceDisabledException) {
    return 'Konum servisleri kapalı, lütfen cihaz ayarlarından konumu açın';
  }
  if (error is PermissionDeniedException) {
    return 'Konum izni verilmedi, lütfen ayarlardan izin verin';
  }
  if (error is MobileScannerException) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Kamera izni verilmedi, lütfen ayarlardan izin verin';
      case MobileScannerErrorCode.unsupported:
        return 'Bu cihazda kamera taraması desteklenmiyor';
      default:
        return 'Kamera başlatılamadı, lütfen tekrar deneyin';
    }
  }
  // image_picker (kamera/galeri) ve flutter_secure_storage'ın platform
  // katmanından fırlattığı hatalar hep PlatformException'dır — .code alanı
  // pakete göre değişir (bkz. image_picker "camera_access_denied" /
  // "photo_access_denied"), ama kullanıcıya tek tip anlaşılır bir mesaj
  // yeterli; teknik .code kDebugMode logunda zaten yukarıda tutuluyor.
  if (error is PlatformException) {
    switch (error.code) {
      case 'camera_access_denied':
        return 'Kamera erişimi reddedildi, lütfen ayarlardan izin verin';
      case 'photo_access_denied':
        return 'Galeri erişimi reddedildi, lütfen ayarlardan izin verin';
      default:
        return 'Cihaz özelliğine erişilirken bir sorun oluştu, lütfen tekrar deneyin';
    }
  }
  if (error is ApiException) {
    switch (error.statusCode) {
      case 401:
        return 'Oturumunuz sona ermiş, lütfen tekrar giriş yapın';
      case 403:
        return 'Bu işlem için yetkiniz bulunmuyor';
      case 404:
        return 'Aranan kayıt bulunamadı';
      case 429:
        return 'Çok fazla istek gönderildi, lütfen biraz bekleyin';
      case 500:
      default:
        return 'Sunucuda bir hata oluştu, lütfen daha sonra tekrar deneyin';
    }
  }

  return 'Beklenmeyen bir hata oluştu, lütfen tekrar deneyin';
}
