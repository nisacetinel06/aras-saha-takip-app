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
"""
import numpy as np
import pandas as pd

from feature_utils import EQUIPMENT_TYPES

N_SAMPLES = 1800
RANDOM_SEED = 42

# Ekipman tipine göre taban risk farkı — trafo ve kesici, sürekli elektriksel/
# mekanik yük altında çalışan ve iç bileşen sayısı daha fazla olan ekipmanlar
# olduğu için (elektrik mühendisliği açısından) direk/sayaca göre biraz daha
# riskli kabul edilir. Bu, gerçek arıza istatistiklerinden değil, alan
# uzmanlığına dayalı makul bir varsayımdan gelir.
TYPE_BASE_RISK = {
    "trafo": 0.2,
    "kesici": 0.2,
    "direk": 0.0,
    "sayac": 0.0,
}

# PROMPT'taki risk_puanı formülü, ham haliyle sigmoid'e verildiğinde
# özelliklerin (yaş, bakım, arıza sayısı) doğal varyansı sigmoid'in tepki
# verdiği ölçeğe göre çok küçük kalıyor — bu da neredeyse tüm kayıtların
# olasılığının aynı orta banda ('gri bölge') sıkışmasına, dolayısıyla model
# için ayırt edilemez, aşırı gürültülü bir eğitim setine yol açıyordu. RISK_SCALE
# bu doğal sinyali sigmoid'in ayırt edebileceği bir ölçeğe büyütür; SIGMOID_SHIFT
# ise ortalama kaydı olasılık eksenin ortasına (~0.25-0.3) getirir.
RISK_SCALE = 3.2
SIGMOID_SHIFT = 3.9


def sigmoid(x):
    return 1 / (1 + np.exp(-x))


def generate(n=N_SAMPLES, seed=RANDOM_SEED):
    rng = np.random.default_rng(seed)

    # Gamma dağılımı: çoğu ekipman genç/yakın bakımlı, azınlık çok eski/uzun
    # süredir bakımsız — sahada gerçekçi bir "uzun kuyruk" dağılımı.
    equipment_age_years = rng.gamma(shape=2.0, scale=4.0, size=n).clip(0, 30)
    months_since_maintenance = rng.gamma(shape=2.0, scale=8.0, size=n).clip(0, 60)
    past_fault_count = rng.poisson(lam=2.2, size=n).clip(0, 15)
    avg_load_factor = rng.normal(loc=0.75, scale=0.2, size=n).clip(0.3, 1.2)
    equipment_type = rng.choice(EQUIPMENT_TYPES, size=n)

    type_bias = np.array([TYPE_BASE_RISK[t] for t in equipment_type])

    # PROMPT'ta belirtilen kural tabanlı risk fonksiyonu (RISK_SCALE ile
    # ölçeklendirilmiş hâli — bkz. yukarıdaki not):
    risk_score = (
        RISK_SCALE
        * (
            equipment_age_years * 0.03
            + months_since_maintenance * 0.02
            + past_fault_count * 0.08
            + np.clip(avg_load_factor - 1.0, 0, None) * 0.5
        )
        + type_bias
    )

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
