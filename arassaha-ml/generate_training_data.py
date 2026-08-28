"""
Modül 9 (Arıza Risk Tahmini) — sentetik eğitim verisi üretici.

DÜRÜSTLÜK NOTU (bkz. README.md): Bu script GERÇEK arıza kayıtlarından değil,
kural tabanlı bir olasılık fonksiyonundan üretilmiş SENTETİK bir veri seti
oluşturur. ArasSaha'nın henüz yıllara yayılan gerçek bir arıza geçmişi
olmadığı için, gerçek veri toplanana kadar makine öğrenmesi ardışık
düzeninin (veri -> eğitim -> servis -> entegrasyon) uçtan uca ÇALIŞTIĞINI
göstermek amacıyla bu yaklaşım kullanılıyor. Gerçek üretim ortamında bu
script tamamen devre dışı bırakılır; yerine ArasSaha'nın SQLite/veri
ambarında biriken gerçek `work_orders` + `equipment` geçmişinden türetilmiş
bir eğitim seti kullanılır.

TEST-19 GÜNCELLEMESİ — "daha az temiz, daha gerçekçi" sentetik veri: önceki
sürüm, tüm özellikleri TEK bir doğrusal formülle topluyordu (özellik
etkileşimi yok, ekipman tipleri arasında yalnızca sabit bir bias farkı vardı,
gürültü düşüktü) — bu, modelin gerçek bir "desen öğrenmesi" yerine formülü
neredeyse birebir ezberlemesine yol açıyordu (bkz. train_model.py'daki eski
sonuçlar: test seti metrikleri gerçekçi olmayacak kadar yüksekti). Bu sürüm
dört değişiklik getiriyor: (1) yaş x bakım aralığı doğrusal olmayan
etkileşim terimi, (2) ekipman tipine göre AYRI ağırlık setleri (yalnızca
sabit bias değil), (3) belirgin biçimde artırılmış etiket gürültüsü, (4)
mevsimsel yük dalgalanmasının gerçekten etikete yansıtılması.
"""
import numpy as np
import pandas as pd

from feature_utils import EQUIPMENT_TYPES

N_SAMPLES = 1800
RANDOM_SEED = 42

# Ekipman tipine göre AYRI risk ağırlık setleri — artık yalnızca sabit bir
# bias farkı değil, her özelliğin ekipman tipine göre FARKLI bir etkisi var.
# Mühendislik sezgisi: trafo/kesici sürekli elektriksel/mekanik yük altında
# çalışır, iç bileşen sayısı fazladır — yaşlandıkça bozulma hızı direk/sayaca
# göre orantısız artar (aşınma doğrusal değil, kümülatiftir). Direk büyük
# ölçüde pasif/yapısal bir bileşendir (yaşın etkisi daha yavaş); sayaç
# elektronik bir cihazdır, yaşlanma etkisi var ama mekanik yorulma yok.
#   age_weight:         yaşın (yıl başına) risk katkısı
#   maint_weight:       bakımdan geçen sürenin (ay başına) risk katkısı
#   interaction_weight: age_maintenance_interaction teriminin çarpanı
#   fault_weight:       geçmiş arıza sayısının (adet başına) risk katkısı
#   load_weight:        aşırı yüklenmenin (load_factor - 1.0, pozitifse) risk katkısı
#   base_bias:          tip bazlı sabit taban risk farkı (kalan artık/residual)
TYPE_RISK_WEIGHTS = {
    "trafo":  {"age_weight": 0.042, "maint_weight": 0.022, "interaction_weight": 0.85, "fault_weight": 0.085, "load_weight": 0.65, "base_bias": 0.15},
    "kesici": {"age_weight": 0.038, "maint_weight": 0.020, "interaction_weight": 0.75, "fault_weight": 0.080, "load_weight": 0.55, "base_bias": 0.12},
    "direk":  {"age_weight": 0.014, "maint_weight": 0.010, "interaction_weight": 0.25, "fault_weight": 0.070, "load_weight": 0.20, "base_bias": 0.00},
    "sayac":  {"age_weight": 0.011, "maint_weight": 0.011, "interaction_weight": 0.20, "fault_weight": 0.070, "load_weight": 0.15, "base_bias": 0.00},
}

# PROMPT'taki risk_puanı formülü, ham haliyle sigmoid'e verildiğinde
# özelliklerin (yaş, bakım, arıza sayısı) doğal varyansı sigmoid'in tepki
# verdiği ölçeğe göre çok küçük kalıyor — bu da neredeyse tüm kayıtların
# olasılığının aynı orta banda ('gri bölge') sıkışmasına, dolayısıyla model
# için ayırt edilemez, aşırı gürültülü bir eğitim setine yol açıyordu. RISK_SCALE
# bu doğal sinyali sigmoid'in ayırt edebileceği bir ölçeğe büyütür; SIGMOID_SHIFT
# ise ortalama kaydı olasılık eksenin ortasına (~0.25-0.3) getirir.
RISK_SCALE = 3.2
SIGMOID_SHIFT = 4.6

# Etiket gürültüsü — önceki sürümde neredeyse yoktu (etiket kararı risk
# formülüyle birebir örtüşüyordu, model formülü ezberliyordu). Burada, risk
# skoru sigmoid'e girmeden ÖNCE numpy.random.normal ile gerçek bir "ölçüm
# belirsizliği/kayıt dışı faktörler" gürültüsü ekleniyor — gerçek dünyada da
# iki özdeş görünen ekipmandan biri arızalanıp diğeri arızalanmayabilir
# (bakım kalitesi, üretim toleransı, şans gibi modele hiç girmeyen
# faktörler). NOISE_STD, sinyali tamamen boğmayacak ama modelin test seti
# metriklerinin gerçekçi (mükemmele yakın DEĞİL) çıkmasını sağlayacak ölçüde
# seçildi — bkz. train_model.py'daki yeni sonuçlarla karşılaştırma.
NOISE_STD = 0.85

# Mevsimsel yük dalgalanması — kış (ısıtma, Ara/Oca/Şub) ve yaz (soğutma,
# Haz/Tem/Ağu) aylarında şebeke yükü tepe yapar; bu dönemlerde ölçülmüş/
# bildirilmiş bir ekipmanın gerçek anlık yükü, "tipik" ortalamasının
# üzerine çıkar. Önceki sürümde "mevsimsel dalgalanma" yalnızca sözde
# bahsediliyordu, etikete hiç yansımıyordu. Burada her kayda rastgele bir
# "gözlem ayı" atanıp bu ayın mevsimsel çarpanı avg_load_factor'e VE ayrıca
# (yüke bağlı olmayan, örn. donma/genleşme kaynaklı ekstra malzeme
# yorulması gibi) doğrudan küçük bir risk terimine yansıtılıyor.
#
# TASARIM NOTU: "gözlem ayı" yalnızca ÜRETİM ANINDA (bu script) kullanılan
# gizli bir değişkendir, FEATURE_COLUMNS'a (feature_utils.py) EKLENMEDİ —
# yani model bunu doğrudan bir girdi olarak görmüyor. Bunun yerine mevsimsel
# etki, gerçek hayatta zaten olduğu gibi avg_load_factor'ün DOĞAL bir parçası
# olarak sızdırılıyor (gerçek üretimde avg_load_factor SCADA/sayaç
# verisinden hesaplanacağı için o veri zaten mevsimsel dalgalanmayı
# doğal olarak taşır) — modele yeni bir canlı API girdisi eklemek
# (routes/risk.js + Flutter değişikliği gerektirirdi) bu görevin kapsamını
# gereğinden fazla büyütürdü; asıl kazanım, sentetik ETİKETLERİN artık bu
# gerçek dünya dalgalanmasını yansıtması.
WINTER_MONTHS = {12, 1, 2}
SUMMER_PEAK_MONTHS = {6, 7, 8}
SEASONAL_LOAD_BONUS = 0.12  # kış/yaz tepe aylarında avg_load_factor'e eklenen ortalama
SEASONAL_RISK_BONUS = 0.18  # aynı ayların, yükten bağımsız doğrudan risk katkısı


def sigmoid(x):
    return 1 / (1 + np.exp(-x))


def generate(n=N_SAMPLES, seed=RANDOM_SEED):
    rng = np.random.default_rng(seed)

    # Gamma dağılımı: çoğu ekipman genç/yakın bakımlı, azınlık çok eski/uzun
    # süredir bakımsız — sahada gerçekçi bir "uzun kuyruk" dağılımı.
    equipment_age_years = rng.gamma(shape=2.0, scale=4.0, size=n).clip(0, 30)
    months_since_maintenance = rng.gamma(shape=2.0, scale=8.0, size=n).clip(0, 60)
    past_fault_count = rng.poisson(lam=2.2, size=n).clip(0, 15)
    equipment_type = rng.choice(EQUIPMENT_TYPES, size=n)

    # Gözlem ayı — yalnızca üretim anında kullanılan gizli değişken (bkz.
    # yukarıdaki TASARIM NOTU), 1-12 arasında uniform.
    observation_month = rng.integers(1, 13, size=n)
    is_peak_season = np.isin(observation_month, list(WINTER_MONTHS | SUMMER_PEAK_MONTHS))

    seasonal_load_noise = np.where(
        is_peak_season,
        rng.normal(loc=SEASONAL_LOAD_BONUS, scale=0.05, size=n),
        rng.normal(loc=0.0, scale=0.05, size=n),
    )
    avg_load_factor = (rng.normal(loc=0.75, scale=0.2, size=n) + seasonal_load_noise).clip(0.3, 1.3)

    # Doğrusal olmayan yaş x bakım-aralığı etkileşimi: 20 yaşındaki bir
    # ekipmanın 6 aylık bakım boşluğu, 2 yaşındaki aynı boşluktan ORANTISIZ
    # daha risklidir (aşınmış/yorulmuş malzeme, taze malzemeye göre bakım
    # eksikliğine çok daha duyarlıdır). **1.5 üssü bu orantısızlığı
    # (doğrusal DEĞİL, süper-doğrusal) modelliyor.
    age_maintenance_interaction = (equipment_age_years / 10) * (months_since_maintenance / 12) ** 1.5

    risk_score = np.zeros(n)
    for t in EQUIPMENT_TYPES:
        mask = equipment_type == t
        w = TYPE_RISK_WEIGHTS[t]
        risk_score[mask] = (
            equipment_age_years[mask] * w["age_weight"]
            + months_since_maintenance[mask] * w["maint_weight"]
            + age_maintenance_interaction[mask] * w["interaction_weight"]
            + past_fault_count[mask] * w["fault_weight"]
            + np.clip(avg_load_factor[mask] - 1.0, 0, None) * w["load_weight"]
            + w["base_bias"]
        )

    risk_score = RISK_SCALE * risk_score
    risk_score += np.where(is_peak_season, SEASONAL_RISK_BONUS, 0.0)

    # Etiket gürültüsü — sigmoid'e girmeden ÖNCE eklenir (bkz. NOISE_STD notu).
    risk_score += rng.normal(loc=0.0, scale=NOISE_STD, size=n)

    probability = sigmoid(risk_score - SIGMOID_SHIFT)
    # numpy.random.binomial: yüksek risk puanlı kayıtların ÇOĞU ama HEPSİ
    # DEĞİL will_fail=1 olsun diye — deterministik bir eşik yerine olasılıksal
    # örnekleme kullanılır (gerçekçi gürültü/varyans).
    will_fail = rng.binomial(1, probability)

    df = pd.DataFrame(
        {
            "equipment_age_years": np.round(equipment_age_years, 2),
            "months_since_maintenance": np.round(months_since_maintenance, 1),
            "past_fault_count": past_fault_count,
            "equipment_type": equipment_type,
            "avg_load_factor": np.round(avg_load_factor, 3),
            "will_fail": will_fail,
        }
    )
    return df


if __name__ == "__main__":
    df = generate()
    df.to_csv("training_data.csv", index=False)

    positive_rate = df["will_fail"].mean()
    print(f"{len(df)} satırlık sentetik eğitim verisi 'training_data.csv' olarak kaydedildi.")
    print(f"will_fail=1 oranı: %{positive_rate * 100:.1f}")
    print("\nEkipman tipine göre dağılım:")
    print(df["equipment_type"].value_counts())
    print("\nEkipman tipine göre will_fail oranı (tip bazlı ağırlıkların GERÇEKTEN")
    print("farklı çalıştığının kanıtı — trafo/kesici, direk/sayaçtan belirgin yüksek olmalı):")
    print(df.groupby("equipment_type")["will_fail"].mean().round(3))
