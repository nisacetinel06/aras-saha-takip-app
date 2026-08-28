# ArasSaha ML Servisi — Arıza Risk Tahmini (Modül 9) + Arıza Açıklaması Otomatik Sınıflandırma (Modül 10) + Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11)

Bu klasör, Node.js/Express backend'inden HTTP ile çağrılan bağımsız bir
Python (FastAPI) servisidir. `arassaha-backend`'e hiçbir şekilde import
edilmez; iki taraf da yalnızca HTTP üzerinden konuşur ve birbirinden
bağımsız başlatılıp durdurulabilir.

## Dürüstlük Notu (önemli)

**Bu modeldeki eğitim verisi (`training_data.csv`) sentetiktir.** Gerçek bir
üretim sisteminde bu tür bir modeli anlamlı şekilde eğitmek için yıllarca
birikmiş gerçek arıza/bakım geçmişi gerekir; ArasSaha prototipinde henüz
böyle bir veri seti yok. Bunun yerine, `generate_training_data.py` içinde
tanımlı, elektrik mühendisliği açısından makul kural tabanlı bir olasılık
fonksiyonuyla (ekipman yaşı, son bakımdan geçen süre, geçmiş arıza sayısı,
yük faktörü ve ekipman tipine göre ağırlıklandırılmış) sentetik bir veri
seti üretilip model bunun üzerinde eğitiliyor.

Bu, gerçek veri toplanana kadar saha projelerinde yaygın ve kabul gören bir
başlangıç yaklaşımıdır: **model eğitimi, servis mimarisi ve Node.js/Flutter
entegrasyonu gerçektir; sahte olan yalnızca eğitim verisidir.** Gerçek
üretim ortamına geçildiğinde tek yapılması gereken, `generate_training_data.py`
yerine ArasSaha'nın gerçek `work_orders`/`equipment` geçmişinden türetilmiş
bir CSV vermek ve `train_model.py`'yi bununla yeniden çalıştırmaktır — model
mimarisi, feature seti ve servis kodu değişmeden kalır.

### TEST-19 Güncellemesi — daha gerçekçi sentetik veri + gerçek geri bildirim döngüsü altyapısı

**Bu görevde yapılan iyileştirmeler, yukarıdaki sentetik veri sınırını
ORTADAN KALDIRMIYOR** — hâlâ gerçek bir arıza geçmişi yerine kural tabanlı
üretilmiş veriyle eğitiliyoruz. Yapılan iki şey, dürüstçe söylemek gerekirse:

1. **Daha gerçekçi bir sentetik TEMEL kuruldu** (bkz. `generate_training_data.py`):
   yaş × bakım aralığı arasında doğrusal olmayan bir etkileşim terimi,
   ekipman tipine göre AYRI risk ağırlık setleri (önceden yalnızca sabit bir
   bias farkı vardı), belirgin biçimde artırılmış etiket gürültüsü
   (`NOISE_STD`) ve mevsimsel yük dalgalanmasının etikete gerçekten
   yansıtılması eklendi. `train_model.py`'a da 5-fold cross-validation,
   hiperparametre araması (RandomizedSearchCV) ve kalibrasyon kontrolü
   (`calibration_curve` + gerekirse `CalibratedClassifierCV`) eklendi — bu,
   modelin sentetik veri ÜZERİNDE daha güvenilir/tutarlı ölçülmesini sağlar,
   ama ölçülen şey hâlâ sentetik veridir.
2. **Zamanla GERÇEK veriye geçişin altyapısı hazırlandı**, henüz DEVREYE
   ALINMADI: `arassaha-backend`'deki `risk_prediction_outcomes` tablosu artık
   her risk tahminini ve (varsa) o ekipmanın GERÇEKTEN arızalanıp
   arızalanmadığını otomatik olarak biriktiriyor (bkz.
   `arassaha-backend/routes/risk.js`, `README.md` "Gerçek Geri Bildirim
   Döngüsü"). `train_model.py`'daki `retrain_with_real_outcomes()` fonksiyonu
   bu gerçek sonuçları sentetik veriyle karıştırıp (gerçek kayıtlara daha
   yüksek örnek ağırlığı vererek) yeniden eğitim yapabilecek şekilde YAZILDI
   ama `__main__` bloğunda ÇAĞRILMIYOR — ArasSaha birkaç ay gerçek kullanımda
   kaldıktan sonra (en az `MIN_REAL_OUTCOMES_FOR_RETRAIN=50` sonuçlanmış
   tahmin birikince) bu altyapı devreye alınabilir.

Özetle: bugün hâlâ sentetik veriyle eğitilen bir modelimiz var, ama (a) bu
sentetik veri öncekinden daha gerçekçi bir sinyal taşıyor ve (b) gerçek
veriye kademeli geçiş için gereken borular (tahmin/sonuç kaydı, yeniden
eğitim fonksiyonu) artık yerinde — eksik olan tek şey, o boruları
DOLDURACAK zamanın kendisi.

## Kurulum

```bash
cd arassaha-ml
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux
pip install -r requirements.txt
```

### `requirements.txt` mi, `requirements.lock.txt` mi?

`requirements.txt`'teki 11 paket (fastapi, uvicorn, scikit-learn, pandas,
numpy, joblib, tensorflow, pillow, matplotlib, kaggle, python-multipart) bu
servisin **doğrudan** bağımlılıklarıdır ve hepsi kesin sürümlere (`==`)
sabitlenmiştir — ama her biri kendi içinde başka paketlere (transitif
bağımlılıklar: numpy, scipy, protobuf, grpcio, pydantic, ~80 paket daha)
ihtiyaç duyar; bunlar `requirements.txt`'te sabitlenmediği için "aynı
requirements.txt, farklı zamanlarda farklı transitif sürümler" riski
sürer. `requirements.lock.txt`, `pip freeze` ile üretilmiş, o an kurulu
OLAN her şeyi (doğrudan + transitif, hepsi kesin sürümle, ~89 paket) içeren
tam bir lockfile'dır.

**Geliştirme sırasında `pip install -r requirements.txt` kullanılabilir,
ama üretim/CI ortamlarında tam yeniden üretilebilirlik için
`pip install -r requirements.lock.txt` tercih edilmelidir.**

`requirements.lock.txt`'i yeniden üretmek (ör. `requirements.txt`'e yeni
bir doğrudan bağımlılık eklendiğinde) için:

```bash
python -m venv fresh_env
fresh_env\Scripts\activate       # Windows
pip install -r requirements.txt
pip freeze > requirements.lock.txt
```

## Modeli eğitme

```bash
python generate_training_data.py   # training_data.csv oluşturur
python train_model.py              # models/risk_model.pkl ve model_metadata.json oluşturur
```

`train_model.py` çalıştıktan sonra konsola test doğruluğu, precision,
recall, F1 ve özellik önem sıralaması yazdırılır; aynı bilgiler
`models/model_metadata.json` içine de kalıcı olarak kaydedilir (modelin
"kimlik kartı").

## Servisi başlatma

```bash
uvicorn app:app --reload --port 8000
```

- `GET /health` — servis ve model yüklü mü kontrolü
- `POST /predict` — tek bir ekipman için risk skoru (Modül 9)
- `POST /classify-text` — bir arıza açıklama metni için arıza tipi/öncelik önerisi (Modül 10)
- `POST /detect-anomaly` — bir sayacın tüketim özelliklerinden anomali skoru (Modül 11)

Node.js backend'i bu servise `ML_SERVICE_URL` ortam değişkeniyle
(varsayılan `http://localhost:8000`) bağlanır (bkz. `arassaha-backend/routes/risk.js`
ve `arassaha-backend/routes/nlp.js`).

## Modül 10 — Arıza Açıklaması Otomatik Sınıflandırma

```bash
python generate_text_training_data.py   # text_training_data.csv oluşturur
python train_text_model.py              # models/tfidf_vectorizer.pkl, text_type_model.pkl, text_priority_model.pkl, text_model_metadata.json oluşturur
```

**İki farklı ML yaklaşımı, tek serviste:** Modül 9, SAYISAL/tablosal ekipman
verisinden (yaş, bakım süresi, geçmiş arıza sayısı vb.) `RandomForestClassifier`
ile risk skoru üretir. Modül 10 ise BİLİNÇLİ olarak farklı bir teknikle
çalışır: serbest METİN arıza açıklamasını `TfidfVectorizer` ile sayısal bir
vektöre çevirip iki ayrı `LogisticRegression` modeliyle (biri arıza tipi,
biri öncelik için) sınıflandırır. İki teknik de aynı `arassaha-ml` FastAPI
servisinde, tek bir `uvicorn` process'inde birlikte çalışır — ayrı bir servis
kurulmadı. Aynı dürüstlük ilkesi burada da geçerlidir: eğitim verisi
(`text_training_data.csv`) gerçek şirket arıza kayıtları değil, şablon tabanlı
üretilmiş sentetik Türkçe metinlerdir (bkz. `generate_text_training_data.py`);
gerçek üretim ortamında model, ArasSaha'nın gerçek arıza açıklama
metinleriyle yeniden eğitilir.

## Modül 11 — Kayıp-Kaçak / Anormal Tüketim Tespiti

**EDAŞ için gerçek finansal değer:** Kayıp-kaçak oranı (dağıtılan enerji ile
faturalandırılan enerji arasındaki fark), elektrik dağıtım şirketleri için
doğrudan bir gelir kaybı kalemidir. Kaçak kullanım veya arızalı/kurcalanmış
sayaçların erken tespiti, sahaya rastgele değil HEDEFLİ ekip gönderilmesini
sağlayarak hem kayıpları azaltır hem de denetim maliyetini düşürür — bu modül
bu ihtiyacı doğrudan karşılamayı amaçlar.

```bash
python generate_consumption_data.py   # meter_consumption tablosunu + consumption_training_data.csv'yi oluşturur
python train_anomaly_model.py         # models/anomaly_model.pkl ve anomaly_model_metadata.json oluşturur
```

`generate_consumption_data.py`, DİĞER `generate_*.py` scriptlerinden farklı
olarak yalnızca bir CSV üretmez — `arassaha-backend/aras_saha.db` dosyasını
(Node.js'in kullandığı SQLite dosyasının aynısı) doğrudan okuyup/yazar: önce
`equipment_type='sayac'` olan ekipmanları okur, sonra ürettiği 12 aylık ham
tüketim verisini `meter_consumption` tablosuna yazar. Bu yüzden ÖNCE
`arassaha-backend` içinde `node seed.js` çalıştırılmış olmalı (en az 15-20
sayaç ekipmanı için).

**Üçüncü ML tekniği, aynı serviste:** Modül 9 (RandomForest, sayısal risk
tahmini) ve Modül 10 (TF-IDF+LogisticRegression, metin sınıflandırma) hem
DENETİMLİ (supervised) tekniklerdir — "doğru cevap" (will_fail, arıza
tipi/öncelik) eğitim verisinde zaten etiketli. Modül 11 BİLİNÇLİ olarak
DENETİMSİZ (unsupervised) bir teknikle çalışır: `IsolationForest`,
"anormal" etiketi olmadan, yalnızca özniteliklerin (ortalama tüketim, düşüş
oranı, ay-ay değişim, sıfıra yakın ay sayısı vb.) dağılımına bakarak ayrık
duran noktaları tespit eder. Isolation Forest kara kutu olduğu için, kullanıcıya
"neden şüpheli" sorusuna somut bir yanıt verebilmek amacıyla `app.py`'deki
`/detect-anomaly` endpoint'i, model skorunun YANINDA basit, açıklanabilir
kurallar da değerlendirir (örn. "Son 3 ayda tüketim %73 azaldı").

**Dürüstlük Notu:** ArasSaha'nın elinde gerçek bir AMI/akıllı sayaç okuma
sistemi yok; `consumption_training_data.csv` ve `meter_consumption` verisi,
`generate_consumption_data.py` içinde tanımlı kural tabanlı bir üreticiyle
(çoğu sayaç mevsimsel/düşük varyanslı normal bir örüntü izler, küçük bir kısmı
BİLEREK ani düşüş / sıfıra yakın tüketim / düzensiz dalgalanma örüntülerinden
biriyle üretilir) sentetiktir. Model eğitimi, servis mimarisi ve Node.js/
Flutter entegrasyonu gerçektir; gerçek üretim ortamında tek yapılması gereken,
`generate_consumption_data.py` yerine ArasSaha'nın gerçek AMI/sayaç okuma
sisteminden türetilmiş bir tüketim geçmişi vermek ve `train_anomaly_model.py`'yi
bununla yeniden çalıştırmaktır.

## Modül 15 — Görüntü Tabanlı Hasar Tespiti

**Veri seti kaynağı:** [Power Line Components Images Dataset](https://www.kaggle.com/datasets/abdulbasit89/power-line-components-images-dataset)
(Kaggle kullanıcısı: **abdulbasit89**), lisans **CC0-1.0** (kamu malı — atıf
zorunlu değil, yine de akademik/staj dürüstlüğü açısından burada ve
`train_damage_model.py`/`organize_dataset.py` içinde açıkça belirtilir). Veri
seti, bir elektrik dağıtım sistemindeki izolatör, dropout-cutout, trafo
bushing, direk ve çapraz kol bileşenlerinin görsellerini; disk izolatör, pin
izolatör, dropout ve trafo bushing için ayrıca yapay olarak üretilmiş hasarlı
("defective") versiyonlarıyla birlikte içerir (10.343 görsel, ~%40 hasarlı /
%60 hasarsız).

```bash
# 1) Kaggle API token'ı ~/.kaggle/kaggle.json'a yerleştirildikten sonra:
kaggle datasets download -d abdulbasit89/power-line-components-images-dataset -p raw_dataset --unzip

# 2) Ham veri setini train/hasarli|hasarsiz, val/..., test/... yapısına dönüştürür
python organize_dataset.py

# 3) MobileNetV2 transfer learning + fine-tuning (models/damage_model.keras,
#    models/damage_model_metadata.json, training_history.png, confusion_matrix.png,
#    misclassified_examples.png üretir) — CPU'da ~30-70 dakika sürebilir.
python train_damage_model.py
```

**Mimari — 2 aşamalı Transfer Learning:** MobileNetV2 (ImageNet ağırlıkları,
`include_top=False`) temel alınır. Aşama 1'de yalnızca eklenen
`GlobalAveragePooling2D -> Dropout(0.3) -> Dense(1, sigmoid)` katmanları
eğitilir (MobileNetV2 dondurulmuş, `lr=1e-3`). Aşama 2'de (fine-tuning)
MobileNetV2'nin son 30 katmanı çözülüp çok düşük bir öğrenme oranıyla
(`lr=1e-5`) birkaç epoch daha eğitilir — transfer learning'in en performans
artırıcı adımı budur. `EarlyStopping`(val_loss, patience=5) ve
`ModelCheckpoint`(en iyi val_accuracy) her iki aşamada da kullanılır.

**Diğer modellerden mimari fark — build zamanında YENİDEN EĞİTİLMEZ:** Modül
9/10/11'in `.pkl` modelleri sentetik veriyle saniyeler içinde eğitildiği için
Dockerfile'da her build'de yeniden üretilir. `damage_model.keras` gerçek bir
veri setiyle ve ~30-70 dakika süren bir süreçle eğitildiği için bu desenin
DIŞINDA tutulur: yalnızca LOKALDE bir kez eğitilir, sonuç dosyası
(`models/damage_model.keras` + `models/damage_model_metadata.json`) git'e
commit edilir (bkz. `.gitignore` içindeki istisna), Dockerfile bunu build
zamanında yeniden eğitmek yerine olduğu gibi imaja kopyalar.

**Dürüstlük Notu:** Bu modül, Modül 9/10/11'den FARKLI olarak sentetik değil
gerçek/halka açık bir veri setiyle eğitildi — ama bu veri setindeki "hasarlı"
görseller de yapay olarak üretilmiş (defective) versiyonlar, ArasSaha'nın
kendi sahasından toplanmış gerçek arıza fotoğrafları değil. Model
eğitimi/servis/entegrasyon süreci gerçektir; gerçek üretimde bu model,
ArasSaha'nın gerçek İSG/iş emri fotoğraflarıyla (zamanla biriktikçe) yeniden
eğitilmelidir — mimari/entegrasyon hiçbir değişiklik gerektirmez.

### TEST-20 Güncellemesi — domain shift'i azaltma + gerçek geri bildirim döngüsü

**Bu iyileştirmeler domain shift sorununu ANINDA ÇÖZMÜYOR** — Kaggle veri
setiyle eğitilen bir model, ilk uygulamada gerçek saha fotoğraflarında hâlâ
kusurlu olabilir; bu BEKLENEN bir durumdur, panik nedeni değildir. Yapılanlar:

1. **Daha agresif veri artırma** (`train_damage_model.py`): RandomZoom
   0.15→0.2, RandomBrightness 0.15→0.3, RandomContrast (YENİ, 0.3),
   GaussianNoise (YENİ, 0.05) — amaç, Kaggle'ın nispeten temiz çekim
   koşullarına değil, telefonla değişken ışık/açı/kalitede çekilmiş gerçek
   saha fotoğraflarına dayanıklılık.
2. **Gerçek dünya doğrulama seti** (`build_real_world_validation_set.py`):
   Wikimedia Commons'tan (CC0/CC-BY/CC-BY-SA, atıfları
   `dataset/real_world_validation/attribution.json`'da) indirilen görseller
   — EĞİTİME KATILMAZ, yalnızca `train_damage_model.py`'nin sonundaki ek bir
   değerlendirme adımında kullanılır. **Dürüst not:** hedef 20-30 görseldi;
   Wikimedia'nın API'si aktif rate-limiting uyguladı (429 yanıtlarında
   "contact noc@wikimedia.org to discuss a less disruptive approach" diyerek
   AÇIKÇA yavaşlamamızı istedi) — bu isteğe saygı göstermek için ısrarcı
   olunmadı, sonuçta **15 görsel** (10 hasarlı, 5 hasarsız) toplanabildi.
   Daha fazlası istenirse `build_real_world_validation_set.py` tekrar
   çalıştırılabilir (kaldığı yerden devam eder, zaten indirilenleri
   tekrar indirmez).
3. **Belirsizlikte "emin değilim" deme** (`app.py` `/classify-image`):
   `damage_probability` 0.35-0.65 arasındaysa (dahil) `is_damaged: null` +
   `confidence_note` döner — Flutter tarafı bu durumda rozet YERİNE nötr bir
   uyarı gösterir (bkz. `isg_report_detail_screen.dart`).
4. **Gerçek geri bildirim döngüsü** (asıl uzun vadeli çözüm): yöneticiler
   İSG bildirimlerini incelerken artık "fotoğrafta gerçekten hasar var
   mıydı?" sorusuna hızlıca Evet/Hayır ile cevap veriyor (bkz.
   `arassaha-backend/routes/isg.js` `PATCH /:id/verify-damage`,
   `isg_reports.human_verified_damage`). `export_real_feedback_data.py`, bu
   doğrulanmış GERÇEK fotoğrafları `dataset/train/hasarli|hasarsiz`'e
   Kaggle verisinin **üzerine** ekler (silmez/değiştirmez). Yeterli miktar
   (50+) birikince `train_damage_model.py` bu karışık veri setiyle yeniden
   çalıştırılabilir — model zamanla hem Kaggle'ın çeşitliliğinden hem
   GERÇEK ArasSaha saha koşullarından öğrenmiş olacak.

Özetle: bu değişiklikler (a) modeli Kaggle dışı görsellere karşı daha
dayanıklı hale getirmeye çalışıyor, (b) gerçekten emin olmadığı durumlarda
bunu itiraf ediyor, ve (c) zamanla gerçek veriye geçişin altyapısını
kuruyor — ama domain shift'in kendisi, yeterli gerçek veri birikene kadar
(muhtemelen aylar) tam olarak çözülmüş SAYILMAMALIDIR.
