// Hiyerarşik görünürlük kuralının (bkz. routes/workOrders.js
// applyVisibilityFilter, liste/harita/dashboard için) TEKİL bir kayda
// doğrudan ID ile erişimdeki karşılığı: teknisyen yalnızca KENDİSİNE atanan
// iş emrine erişebilir; dispeçer/yönetici her zaman muaftır (SEC-02'de
// kurulan orijinal davranış, burada genişletilmiyor, yalnızca ortaklaştırılıyor).
//
// GET /:id, PATCH /:id/status VE POST /:id/photos üçü de AYNI kuralı
// uygulamalı — tek bir yerde tutmak hem kod tekrarını önler hem de ileride
// yeni bir iş emri endpoint'i eklenirken bu kontrolün unutulma riskini azaltır
// (bkz. SEC-03 bulgusu: POST /:id/photos bu kontrolü hiç uygulamıyordu).
//
// NOT: bu fonksiyon `res` nesnesine dokunmaz, yalnızca true/false döner —
// 404 döndürme kararı (403 DEĞİL — "kayıt var ama senin değil" bilgisini
// sızdırmamak için, ID enumeration'a karşı savunma) her zaman ÇAĞIRAN route'ta
// kalır, böylece her endpoint kendi hata mesajını/response şeklini korur.
function assertWorkOrderAccessible(workOrder, user) {
  if (user.role === 'teknisyen' && workOrder.assigned_user_id !== user.id) {
    return false;
  }
  return true;
}

module.exports = { assertWorkOrderAccessible };
