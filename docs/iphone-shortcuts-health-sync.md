# iPhone Shortcuts Health Sync

Amaç: iPhone, Apple Health verisini her gün otomatik okuyup iCloud Drive'a JSON yazsın. Mac app de bu dosyayı otomatik içeri alsın.

Mac app şu dosyayı okur:

```text
iCloud Drive/Shortcuts/Hercules/health-sync.json
```

Eski/alternatif yol da desteklenir:

```text
iCloud Drive/Hercules/health-sync.json
```

## JSON Formatı

Shortcut'un yazacağı metin şu formatta olmalı:

```json
{
  "version": 1,
  "source": "ios-shortcuts",
  "days": [
    {
      "date": "2026-05-22",
      "steps": 7420,
      "distanceMeters": 5230,
      "activeEnergyKcal": 310
    }
  ]
}
```

`date` mutlaka `yyyy-MM-dd` formatında olsun. `distanceMeters` ve `activeEnergyKcal` yoksa Mac app yine adımı içeri alır.

## Shortcut Kurulumu

1. Shortcuts app'i aç.
2. Yeni shortcut oluştur: `Hercules Health Sync`.
3. `Current Date` ekle.
4. `Format Date` ekle:
   - Format: Custom
   - Custom format: `yyyy-MM-dd`
   - Bu değişkeni `DayString` diye kullan.
5. `Find Health Samples` ekle:
   - Type: Steps / Step Count
   - Start Date: Today
   - End Date: Current Date
6. `Get Details of Health Samples` ekle:
   - Detail: Value
7. `Calculate Statistics` ekle:
   - Operation: Sum
   - Bu sonucu `StepsTotal` diye kullan.
8. Aynısını distance için yap:
   - Type: Walking + Running Distance
   - Value toplamını al.
   - Sonuç km geliyorsa `Calculate Expression` ile `DistanceTotal * 1000` yap.
   - Bu sonucu `DistanceMeters` diye kullan.
9. İstersen active energy için de yap:
   - Type: Active Energy
   - Value toplamını al.
   - Bu sonucu `ActiveEnergyKcal` diye kullan.
10. `Text` action ekle ve şu JSON'u yaz:

```json
{
  "version": 1,
  "source": "ios-shortcuts",
  "days": [
    {
      "date": "DAY_STRING",
      "steps": STEPS_TOTAL,
      "distanceMeters": DISTANCE_METERS,
      "activeEnergyKcal": ACTIVE_ENERGY_KCAL
    }
  ]
}
```

Metindeki `DAY_STRING`, `STEPS_TOTAL`, `DISTANCE_METERS`, `ACTIVE_ENERGY_KCAL` yerlerine Shortcuts değişkenlerini koy.

11. `Save File` ekle:
   - File: Text action output
   - Service: iCloud Drive
   - Path: `Shortcuts/Hercules/health-sync.json`
   - Ask Where to Save: Off
   - Overwrite If File Exists: On

## Otomasyon

1. Shortcuts -> Automation -> New Automation.
2. Trigger: Time of Day.
3. Saat: örneğin 23:55.
4. Action: Run Shortcut -> `Hercules Health Sync`.
5. Run Immediately açık olsun; Ask Before Running varsa kapalı olsun.

İlk çalıştırmada Health permission isteyebilir. Bir kere izin verdikten sonra günlük otomasyon dosyayı günceller.

## Mac Tarafı

Mac app:

- Açılışta import eder.
- App aktifleşince import eder.
- Açıkken 5 dakikada bir dosyayı tekrar okur.
- Aynı günü duplicate eklemez, mevcut günlük kaydı günceller.
- Profil ekranında bugün, 7 gün, 30 gün ve günlük ortalama görünür.
