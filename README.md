<div align="center">

<img src="images/ArasAI_LOGO.png" alt="ArasSaha Logo" width="140"/>

# ⚡ ArasSaha

### Aras EDAŞ Saha Ekipleri için Akıllı Arıza & Operasyon Takip Sistemi

**Flutter** mobil uygulama · **Node.js/Express** REST API · **Python/FastAPI** Makine Öğrenmesi servisi

[![Flutter](https://img.shields.io/badge/Flutter-3.11-02569B?logo=flutter&logoColor=white)](arassaha_flutter)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D22.5-339933?logo=node.js&logoColor=white)](arassaha-backend)
[![Express](https://img.shields.io/badge/Express-4.19-000000?logo=express&logoColor=white)](arassaha-backend)
[![FastAPI](https://img.shields.io/badge/FastAPI-ML%20Servisi-009688?logo=fastapi&logoColor=white)](arassaha-ml)
[![SQLite](https://img.shields.io/badge/SQLite-better--sqlite3-003B57?logo=sqlite&logoColor=white)](arassaha-backend)
[![Deploy](https://img.shields.io/badge/Deploy-Railway-0B0D0E?logo=railway&logoColor=white)](https://railway.app)
[![Lisans](https://img.shields.io/badge/Lisans-Staj%20Prototipi-orange)](#-lisans--sorumluluk-reddi)

**[📱 Flutter Uygulaması](arassaha_flutter)** · **[🔧 Backend API](arassaha-backend)** · **[🤖 ML Servisi](arassaha-ml)** · **[🏗️ Mimari Doküman](ARCHITECTURE.md)**

</div>

---

## 🎯 ArasSaha nedir?

ArasSaha, bir elektrik dağıtım şirketinin **saha teknisyeni → dispeçer → yönetici** zincirinde arıza/iş emri yönetimini uçtan uca dijitalleştiren bir mobil operasyon platformudur. Teknisyen sahada telefonundan arızayı görür, fotoğraflar, durumunu günceller; dispeçer ve yönetici aynı anda, farklı bir cihazdan, **gerçek zamanlı** olarak bu veriyi görür.

> **Bu bir staj prototipidir** — veriler (personel, arıza, ekipman) sahtedir/sentetiktir ve gerçek Aras EDAŞ üretim sistemlerine bağlı değildir. Ancak **veri akışı sahte değildir**: her "kaydet" işlemi backend'de gerçekten kalıcı saklanır ve yetkili her kullanıcı tarafından görülebilir. Detaylar için bkz. [ARCHITECTURE.md](ARCHITECTURE.md).

---

## ✨ Öne Çıkan Özellikler

| | |
|---|---|
| 🛠️ **İş Emri / Arıza Yönetimi** | Oluşturma, atama, durum akışı (açık → yolda → sahada → çözüldü), fotoğraf yükleme (gerçek multipart upload) |
| 🗺️ **Canlı Harita** | Açık arızaların konumu (OpenStreetMap / `flutter_map`), pin'den detaya geçiş |
| 📦 **Ekipman Envanteri + QR** | QR kod okutarak trafo/direk/sayaç geçmişine anlık erişim |
| 🧯 **İSG Bildirimi** | Fotoğraf + konumla saha güvenliği risk raporlama, yönetici incelemesi |
| 🔔 **Bildirimler & Yönetici Mesajları** | Uygulama içi bildirim akışı, okunmamış sayaç rozetleri |
| 🆘 **SOS Acil Durum Alarmı** | Teknisyenden dispeçere anlık acil durum bildirimi |
| 📊 **Raporlar & Analitik** | Bölge/ekipman türüne göre arıza dağılımı, malzeme kullanımı, `fl_chart` grafikleri |
| 🧰 **Malzeme/Stok Takibi** | İş emri bazlı malzeme tüketimi, düşük stok uyarıları |
| 🤖 **3 Farklı ML Modeli** | Arıza risk tahmini (RandomForest), açıklama metninden otomatik sınıflandırma (TF-IDF), anormal tüketim/kayıp-kaçak tespiti (Isolation Forest) |
| 🖼️ **Görüntüyle Hasar Tespiti** | MobileNetV2 transfer learning ile fotoğraftan hasar sınıflandırma |
| 🔐 **Güvenlik** | JWT + refresh token rotasyonu, **2FA (TOTP)**, RBAC, brute-force koruması, dosya içerik doğrulama |
| 📜 **KVKK Uyumluluğu** | Kişisel veri özeti, anonimleştirme/silme talebi akışı |
| 🧪 **CI/CD Gate** | Testler ve bağımlılık güvenlik taraması kırmızıysa **deploy otomatik durur** |
| 📱 **Cihaz Yönetimi (MDM Simülasyonu)** | Uzaktan kilitle/senkronize et aksiyonları (kavramsal demo) |

---

## 🏗️ Mimari

```
┌─────────────────────┐        HTTP/JSON (REST)         ┌───────────────────────────┐
│  📱 Flutter Uygulama  │ ───────────────────────────────▶ │  🔧 Node.js + Express API  │
│  Android / iOS        │ ◀─────────────────────────────── │  Auth · RBAC · İş Mantığı  │
└─────────────────────┘                                   └─────────────┬─────────────┘
                                                                         │  SQL (better-sqlite3)
                              HTTP (risk/sınıflandırma/anomali)         ▼
┌─────────────────────┐ ◀──────────────────────────────── ┌───────────────────────────┐
│ 🤖 Python + FastAPI   │                                   │  🗄️ SQLite (aras_saha.db)  │
│ ML Servisi (bağımsız) │ ─────────────────────────────────▶ │  Tek dosya, kalıcı veri    │
└─────────────────────┘                                   └───────────────────────────┘
```

Üç katman birbirinden **tamamen bağımsız** çalışır ve başlatılır: Flutter uygulaması Express API'ye, Express API de (yalnızca risk/ML endpoint'lerinde) FastAPI servisine HTTP üzerinden bağlanır — hiçbir import yoktur. Detaylı şema, veritabanı tabloları ve API listesi için: **[ARCHITECTURE.md](ARCHITECTURE.md)**.

---

## 📂 Proje Yapısı

```
ArasSaha/
├── arassaha_flutter/   📱 Flutter mobil uygulaması (Android/iOS)
├── arassaha-backend/   🔧 Node.js + Express + SQLite REST API
├── arassaha-ml/        🤖 Python + FastAPI ML servisi (risk/sınıflandırma/hasar tespiti)
├── ARCHITECTURE.md      🏗️ Mimari, veritabanı şeması, API listesi, modül planı
└── DESIGN_SYSTEM.md     🎨 Renk paleti, tipografi, bileşen sistemi
```

---

## 🚀 Kurulum

Uygulamayı çalıştırmak için üç bileşeni de (backend, ML servisi, Flutter uygulaması) sırayla kurman gerekiyor. Aşağıdaki adımları takip et — her komut ilgili klasör içinden çalıştırılmalıdır.

### Gereksinimler

- **Node.js** ≥ 22.5
- **Flutter SDK** (Dart ≥ 3.11)
- **Python** 3.10+ (yalnızca ML servisini lokalde çalıştırmak istersen)
- Android Studio / Xcode (emülatör veya fiziksel cihaz için)

### 1️⃣ Backend (Node.js + Express)

```bash
cd arassaha-backend
npm install
npm run seed     # demo/sahte veriyi aras_saha.db'ye yükler
npm start        # http://localhost:3000 üzerinde ayağa kalkar
```

> Ortam değişkenleri için `arassaha-backend/.env` dosyası oluşturman gerekir (`JWT_SECRET`, isteğe bağlı `ML_SERVICE_URL`, `GEMINI_API_KEY`, `FIREBASE_SERVICE_ACCOUNT_JSON` vb.). Backend'e özel test/kurulum detayları için **[arassaha-backend/README.md](arassaha-backend/README.md)**.

### 2️⃣ ML Servisi (Python + FastAPI) — opsiyonel

Risk tahmini, metin sınıflandırma ve hasar tespiti gibi ML özelliklerini lokalde test etmek istersen:

```bash
cd arassaha-ml
python -m venv venv
venv\Scripts\activate          # Windows
pip install -r requirements.txt
python generate_training_data.py && python train_model.py
uvicorn app:app --reload --port 8000
```

Detaylı eğitim/kurulum adımları (3 farklı model + görüntü tabanlı hasar tespiti) için **[arassaha-ml/README.md](arassaha-ml/README.md)**.

### 3️⃣ Flutter Uygulaması

```bash
cd arassaha_flutter
flutter pub get
flutter run
```

> ⚠️ **Önemli:** Uygulama varsayılan olarak **canlı Railway backend'ine** (`https://arassaha-backend-production.up.railway.app`) bağlanır — lokal backend'ini test etmek istiyorsan `--dart-define=API_HOST=http://10.0.2.2:3000` (Android emülatör) gibi bir override vermen gerekir; aksi halde uygulama doğrudan canlı sunucuyla konuşur ve ekstra kurulum yapmana gerek kalmaz.

```bash
# Örnek: lokal backend ile test
flutter run --dart-define=API_HOST=http://10.0.2.2:3000
```

### 🔑 Demo Giriş Bilgileri

`npm run seed` çalıştırıldığında rastgele üretilen kullanıcılardan biriyle giriş yapabilirsin (sicil no + şifre); seed script'inin konsol çıktısında örnek kimlik bilgileri listelenir.

---

## 🧰 Teknoloji Yığını

| Katman | Teknolojiler |
|---|---|
| **Mobil** | Flutter, Dart, Provider (state management), `flutter_map`, `fl_chart`, `mobile_scanner`, `image_picker` |
| **Backend** | Node.js, Express, better-sqlite3 (`node:sqlite`), JWT + refresh token, bcrypt, TOTP (2FA), Multer, node-cron |
| **Veritabanı** | SQLite — dosya tabanlı, kurulumsuz, tek dosya yedekleme |
| **ML Servisi** | Python, FastAPI, scikit-learn (RandomForest, IsolationForest, TF-IDF+LogisticRegression), TensorFlow/Keras (MobileNetV2 transfer learning) |
| **CI/CD** | GitHub Actions — test + `npm audit` / `pip-audit` / OSV-Scanner gate'leri kırmızıysa deploy durur |
| **Deploy** | Railway (backend) |

---

## 🧪 Test & Kalite

```bash
cd arassaha-backend
npm test              # node:test + supertest, izole in-memory veritabanı
npm run test:coverage # coverage raporu
```

Testler production veritabanına **hiçbir zaman** dokunmaz (`NODE_ENV=test` ⇒ `:memory:` SQLite). CI/CD pipeline'ı, testler veya bağımlılık güvenlik taraması (`npm audit --audit-level=high`) kırmızı yandığında production deploy'unu otomatik olarak engeller.

---

## 📄 Dokümantasyon

| Doküman | İçerik |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Sistem mimarisi, veritabanı şeması, tüm API endpoint'leri, modül/geliştirme planı |
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | Renk paleti, tipografi, spacing, bileşen (buton/kart) sistemi |
| [arassaha-backend/README.md](arassaha-backend/README.md) | Backend kurulumu, test yapısı, CI/CD gate detayları |
| [arassaha-backend/SECURITY_NOTES.md](arassaha-backend/SECURITY_NOTES.md) | Güvenlik kararları ve notları |
| [arassaha-ml/README.md](arassaha-ml/README.md) | 3 ML modeli + görüntü tabanlı hasar tespitinin eğitimi ve servis kurulumu |

---

## ⚠️ Lisans / Sorumluluk Reddi

Bu proje bir **staj/eğitim prototipidir**. Uygulamadaki tüm kullanıcı, arıza, ekipman ve tüketim verileri **sentetik/sahte** olarak üretilmiştir; gerçek Aras EDAŞ müşteri, personel veya altyapı bilgisi **içermez** ve üretim (production) sistemlerine bağlı değildir.

---

<div align="center">

Geliştirici: **[nisacetinel06](https://github.com/nisacetinel06)**

<sub>⚡ ile Aras EDAŞ saha ekipleri için tasarlandı.</sub>

</div>
