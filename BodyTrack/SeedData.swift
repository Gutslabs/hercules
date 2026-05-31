import Foundation
import SwiftData

enum DemoSeed {
    /// Hareket kütüphanesinin bir kez tohumlandığını işaretler; kullanıcının
    /// sonradan sildiği varsayılan hareketler tekrar geri gelmesin diye.
    private static let exerciseSeedFlag = "didSeedExerciseLibraryV1"
    /// Mevcut hareket kayıtlarına görsel URL'lerinin bir kez işlendiğini işaretler.
    private static let exerciseImageBackfillFlag = "didBackfillExerciseImagesV1"
    /// Hazır antrenman programlarının bir kez tohumlandığını işaretler.
    private static let programSeedFlag = "didSeedProgramsV1"

    /// free-exercise-db (yuhonas/free-exercise-db, public domain) ham görsel kökü.
    static let imageBaseURL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

    /// Hareket adı → free-exercise-db klasör id'si.
    /// Her klasörde 0.jpg (başlangıç) ve 1.jpg (bitiş) fotoğrafı var; gif hissi için sırayla gösterilir.
    static let exerciseImageIDs: [String: String] = [
        "Eğimli Bench Press": "Barbell_Incline_Bench_Press_-_Medium_Grip",
        "Bench Press": "Barbell_Bench_Press_-_Medium_Grip",
        "Eğimli Dumbbell Press": "Incline_Dumbbell_Press",
        "Dumbbell Bench Press": "Dumbbell_Bench_Press",
        "Machine Chest Press": "Leverage_Chest_Press",
        "Oturarak Cable Fly": "Flat_Bench_Cable_Flyes",
        "Pec Deck": "Butterfly",
        "Cable Crossover": "Cable_Crossover",
        "Dumbbell Fly": "Dumbbell_Flyes",
        "Paralel Bar Dips": "Dips_-_Chest_Version",
        "Şınav": "Pushups",
        "Lat Pulldown (Geniş Tutuş)": "Wide-Grip_Lat_Pulldown",
        "Lat Pulldown (Nötr Tutuş)": "V-Bar_Pulldown",
        "Tek Kol Lat Pulldown": "One_Arm_Lat_Pulldown",
        "Göğüs Destekli Row": "Lying_T-Bar_Row",
        "Oturarak Cable Row": "Seated_Cable_Rows",
        "Barbell Row": "Bent_Over_Barbell_Row",
        "Tek Kol Dumbbell Row": "One-Arm_Dumbbell_Row",
        "Meadows Row": "Bent_Over_One-Arm_Long_Bar_Row",
        "Barfiks (Geniş Tutuş)": "Wide-Grip_Rear_Pull-Up",
        "Barfiks (Nötr Tutuş)": "Pullups",
        "Chin-up": "Chin-Up",
        "Dumbbell Pullover": "Bent-Arm_Dumbbell_Pullover",
        "Deadlift": "Barbell_Deadlift",
        "Cable Lateral Raise": "Cable_Seated_Lateral_Raise",
        "Dumbbell Lateral Raise": "Side_Lateral_Raise",
        "Reverse Pec Deck": "Reverse_Machine_Flyes",
        "Reverse Cable Crossover": "Cable_Rear_Delt_Fly",
        "Face Pull": "Face_Pull",
        "Barbell Overhead Press": "Barbell_Shoulder_Press",
        "Oturarak Dumbbell Shoulder Press": "Dumbbell_Shoulder_Press",
        "Machine Shoulder Press": "Machine_Shoulder_Military_Press",
        "Arnold Press": "Arnold_Dumbbell_Press",
        "Upright Row": "Upright_Barbell_Row",
        "Bayesian Cable Curl": "Standing_Biceps_Cable_Curl",
        "Dumbbell Preacher Curl": "One_Arm_Dumbbell_Preacher_Curl",
        "EZ Bar Curl": "EZ-Bar_Curl",
        "Ayakta Dumbbell Curl": "Dumbbell_Bicep_Curl",
        "Eğimli Dumbbell Curl": "Incline_Dumbbell_Curl",
        "Hammer Curl": "Hammer_Curls",
        "Barbell Curl": "Barbell_Curl",
        "Cable Curl": "Standing_Biceps_Cable_Curl",
        "Overhead Cable Triceps Extension": "Cable_Rope_Overhead_Triceps_Extension",
        "Triceps Pushdown (Bar)": "Triceps_Pushdown",
        "Triceps Pushdown (Halat)": "Triceps_Pushdown_-_Rope_Attachment",
        "Barbell Skullcrusher": "EZ-Bar_Skullcrusher",
        "Tek Kol Dumbbell Overhead Extension": "Dumbbell_One-Arm_Triceps_Extension",
        "Close-Grip Bench Press": "Close-Grip_Barbell_Bench_Press",
        "Cable Triceps Kickback": "Tricep_Dumbbell_Kickback",
        "Dar Tutuş Dips": "Dips_-_Triceps_Version",
        "Barbell Back Squat": "Barbell_Squat",
        "Hack Squat": "Barbell_Hack_Squat",
        "Smith Machine Squat": "Smith_Machine_Squat",
        "Front Squat": "Front_Barbell_Squat",
        "Leg Press (45°)": "Leg_Press",
        "Leg Extension": "Leg_Extensions",
        "Bulgarian Split Squat": "Split_Squat_with_Dumbbells",
        "Hamle (Lunge)": "Dumbbell_Lunges",
        "Goblet Squat": "Goblet_Squat",
        "Oturarak Leg Curl": "Seated_Leg_Curl",
        "Yatarak Leg Curl": "Lying_Leg_Curls",
        "Romanian Deadlift": "Romanian_Deadlift",
        "Stiff-Leg Deadlift": "Stiff-Legged_Barbell_Deadlift",
        "Nordic Curl": "Natural_Glute_Ham_Raise",
        "Barbell Hip Thrust": "Barbell_Hip_Thrust",
        "Machine Hip Thrust": "Barbell_Glute_Bridge",
        "Machine Hip Abduction": "Thigh_Abductor",
        "Cable Pull Through": "Pull_Through",
        "45° Back Extension": "Hyperextensions_Back_Extensions",
        "Yürüyen Hamle": "Barbell_Walking_Lunge",
        "Step Up": "Dumbbell_Step_Ups",
        "Ayakta Calf Raise": "Standing_Calf_Raises",
        "Oturarak Calf Raise": "Seated_Calf_Raise",
        "Leg Press Calf Raise": "Calf_Press_On_The_Leg_Press_Machine",
        "Asılı Bacak Kaldırma": "Hanging_Leg_Raise",
        "Cable Crunch": "Cable_Crunch",
        "Ağırlıklı Crunch": "Crunches",
        "Plank": "Plank",
        "Bisiklet Crunch": "Air_Bike",
        "Russian Twist": "Russian_Twist",
        "Ab Wheel Rollout": "Ab_Roller",
        "Bilek Curl": "Seated_Dumbbell_Palms-Up_Wrist_Curl",
        "Ters Bilek Curl": "Seated_Dumbbell_Palms-Down_Wrist_Curl",
        "Ters Barbell Curl": "Reverse_Barbell_Curl"
    ]

    /// Verilen hareket adı için 0.jpg / 1.jpg URL çiftini virgülle birleştirip döndürür (yoksa nil).
    static func imageURLsRaw(for name: String) -> String? {
        guard let id = exerciseImageIDs[name] else { return nil }
        return "\(imageBaseURL)\(id)/0.jpg,\(imageBaseURL)\(id)/1.jpg"
    }

    static func seedIfEmpty(_ ctx: ModelContext) {
        let profileCount = (try? ctx.fetchCount(FetchDescriptor<UserProfile>())) ?? 0
        let workoutCount = (try? ctx.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0

        if profileCount == 0 {
            let profile = UserProfile(
                name: "",
                sex: .male,
                birthDate: Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now,
                height: 178,
                activity: .moderate,
                goal: .maintain
            )
            ctx.insert(profile)
        }

        if workoutCount == 0 {
            let defaults = [
                WorkoutSession(weekday: 3, name: "Sırt + Göğüs", estimatedCalories: 350),
                WorkoutSession(weekday: 5, name: "Biceps + Triceps", estimatedCalories: 280),
                WorkoutSession(weekday: 7, name: "Karın + Bacak", estimatedCalories: 380)
            ]
            for workout in defaults {
                ctx.insert(workout)
            }
        }

        // Hareket kütüphanesi: yalnızca bir kez, adı zaten kayıtlı olmayanları ekle.
        // Mevcut kullanıcı hareketleri korunur; tekrar çalıştığında çoğaltma yapmaz.
        if !UserDefaults.standard.bool(forKey: exerciseSeedFlag) {
            let existingNames = Set(((try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []).map(\.name))
            for exercise in defaultExercises where !existingNames.contains(exercise.name) {
                ctx.insert(exercise)
            }
            UserDefaults.standard.set(true, forKey: exerciseSeedFlag)
        }

        // Görsel URL'lerini bir kez mevcut kayıtlara işle (önceden tohumlanmış 85 kayıt dahil).
        if !UserDefaults.standard.bool(forKey: exerciseImageBackfillFlag) {
            let all = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
            for exercise in all where exercise.imageURLsRaw == nil {
                exercise.imageURLsRaw = imageURLsRaw(for: exercise.name)
            }
            UserDefaults.standard.set(true, forKey: exerciseImageBackfillFlag)
        }

        // Hazır programlar: bir kez, adı zaten kayıtlı olmayanları ekle.
        if !UserDefaults.standard.bool(forKey: programSeedFlag) {
            let existingNames = Set(((try? ctx.fetch(FetchDescriptor<TrainingProgram>())) ?? []).map(\.name))
            for program in defaultPrograms where !existingNames.contains(program.name) {
                ctx.insert(program)
            }
            UserDefaults.standard.set(true, forKey: programSeedFlag)
        }

        try? ctx.save()
    }

    /// Kanıta dayalı (science-based) başlangıç hareket kütüphanesi.
    /// Seçim ve kademe sıralaması Jeff Nippard egzersiz tier list'lerinden derlenmiştir.
    /// Model yan deltoid için ayrı bölge tutmadığından yana açış hareketleri `frontDelt` (Omuzlar) altında.
    static var defaultExercises: [Exercise] {
        let list: [Exercise] = [
            // MARK: Göğüs (Push)
            Exercise(name: "Eğimli Bench Press", equipment: .barbell,
                     primaryMuscles: [.chest, .frontDelt], secondaryMuscles: [.triceps],
                     category: .push, difficulty: .intermediate,
                     notes: "Üst göğüs için temel bileşik hareket. Bench açısını 30°civarında tut, omuzları sıkıştırma.",
                     variations: ["Eğimli Dumbbell Press", "Bench Press"]),
            Exercise(name: "Bench Press", equipment: .barbell,
                     primaryMuscles: [.chest], secondaryMuscles: [.frontDelt, .triceps],
                     category: .push, difficulty: .intermediate,
                     notes: "Klasik yatay itiş. Barı göğüs ortasına kontrollü indir, tam ROM çalış.",
                     variations: ["Eğimli Bench Press", "Dumbbell Bench Press"]),
            Exercise(name: "Eğimli Dumbbell Press", equipment: .dumbbell,
                     primaryMuscles: [.chest, .frontDelt], secondaryMuscles: [.triceps],
                     category: .push, difficulty: .intermediate),
            Exercise(name: "Dumbbell Bench Press", equipment: .dumbbell,
                     primaryMuscles: [.chest], secondaryMuscles: [.frontDelt, .triceps],
                     category: .push, difficulty: .beginner),
            Exercise(name: "Machine Chest Press", equipment: .machine,
                     primaryMuscles: [.chest], secondaryMuscles: [.frontDelt, .triceps],
                     category: .push, difficulty: .beginner,
                     notes: "Stabil ve güvenli; başarısızlığa yakın çalışmak için ideal (S+ tier)."),
            Exercise(name: "Oturarak Cable Fly", equipment: .cable,
                     primaryMuscles: [.chest], category: .push, difficulty: .intermediate,
                     notes: "Gerili pozisyonda sabit tansiyon sağlar. Haftada 3 set bile büyümenin büyük kısmını verir."),
            Exercise(name: "Pec Deck", equipment: .machine,
                     primaryMuscles: [.chest], category: .push, difficulty: .beginner),
            Exercise(name: "Cable Crossover", equipment: .cable,
                     primaryMuscles: [.chest], category: .push, difficulty: .intermediate),
            Exercise(name: "Dumbbell Fly", equipment: .dumbbell,
                     primaryMuscles: [.chest], category: .push, difficulty: .intermediate,
                     notes: "Gerili pozisyonu vurgular; dirsekleri hafif bükük tut."),
            Exercise(name: "Paralel Bar Dips", equipment: .bodyweight,
                     primaryMuscles: [.chest], secondaryMuscles: [.triceps, .frontDelt],
                     category: .push, difficulty: .intermediate,
                     notes: "Öne eğil → göğüs baskın; dik dur → triceps baskın."),
            Exercise(name: "Şınav", equipment: .bodyweight,
                     primaryMuscles: [.chest], secondaryMuscles: [.triceps, .frontDelt],
                     category: .push, difficulty: .beginner),

            // MARK: Sırt (Pull)
            Exercise(name: "Lat Pulldown (Geniş Tutuş)", equipment: .cable,
                     primaryMuscles: [.lats], secondaryMuscles: [.biceps, .rearDelt],
                     category: .pull, difficulty: .beginner,
                     notes: "Sırt genişliği için S tier. Göğsü yukarı ver, dirsekleri aşağı sür."),
            Exercise(name: "Lat Pulldown (Nötr Tutuş)", equipment: .cable,
                     primaryMuscles: [.lats], secondaryMuscles: [.biceps],
                     category: .pull, difficulty: .beginner),
            Exercise(name: "Tek Kol Lat Pulldown", equipment: .cable,
                     primaryMuscles: [.lats], secondaryMuscles: [.biceps],
                     category: .pull, difficulty: .intermediate,
                     notes: "Tek taraflı çalışır, ROM ve gerilmeyi artırır."),
            Exercise(name: "Göğüs Destekli Row", equipment: .machine,
                     primaryMuscles: [.lats, .traps], secondaryMuscles: [.rearDelt, .biceps],
                     category: .pull, difficulty: .beginner,
                     notes: "En iyi all-around sırt hareketi (S tier); bel yükü olmadan saf kürek."),
            Exercise(name: "Oturarak Cable Row", equipment: .cable,
                     primaryMuscles: [.lats, .traps], secondaryMuscles: [.biceps, .rearDelt],
                     category: .pull, difficulty: .beginner),
            Exercise(name: "Barbell Row", equipment: .barbell,
                     primaryMuscles: [.lats, .traps], secondaryMuscles: [.biceps, .lowerBack, .rearDelt],
                     category: .pull, difficulty: .intermediate),
            Exercise(name: "Tek Kol Dumbbell Row", equipment: .dumbbell,
                     primaryMuscles: [.lats, .traps], secondaryMuscles: [.biceps],
                     category: .pull, difficulty: .beginner),
            Exercise(name: "Meadows Row", equipment: .barbell,
                     primaryMuscles: [.lats, .traps], secondaryMuscles: [.biceps],
                     category: .pull, difficulty: .advanced),
            Exercise(name: "Barfiks (Geniş Tutuş)", equipment: .bodyweight,
                     primaryMuscles: [.lats], secondaryMuscles: [.biceps],
                     category: .pull, difficulty: .advanced),
            Exercise(name: "Barfiks (Nötr Tutuş)", equipment: .bodyweight,
                     primaryMuscles: [.lats], secondaryMuscles: [.biceps],
                     category: .pull, difficulty: .advanced),
            Exercise(name: "Chin-up", equipment: .bodyweight,
                     primaryMuscles: [.lats, .biceps], category: .pull, difficulty: .intermediate),
            Exercise(name: "Dumbbell Pullover", equipment: .dumbbell,
                     primaryMuscles: [.lats], secondaryMuscles: [.chest, .triceps],
                     category: .pull, difficulty: .intermediate),

            // MARK: Tüm Vücut
            Exercise(name: "Deadlift", equipment: .barbell,
                     primaryMuscles: [.glutes, .hamstrings, .lowerBack],
                     secondaryMuscles: [.traps, .lats, .quadriceps],
                     category: .fullBody, difficulty: .advanced,
                     notes: "Nötr bel, kalçadan menteşelen. Ağır bileşik; teknik > yük."),

            // MARK: Omuzlar (Push / Pull)
            Exercise(name: "Cable Lateral Raise", equipment: .cable,
                     primaryMuscles: [.frontDelt], category: .push, difficulty: .beginner,
                     notes: "Yan deltoid için S tier. Sabit tansiyon, kontrollü negatif."),
            Exercise(name: "Dumbbell Lateral Raise", equipment: .dumbbell,
                     primaryMuscles: [.frontDelt], category: .push, difficulty: .beginner,
                     notes: "Hafifçe öne eğilmek (lean-in) gerilmeyi artırır."),
            Exercise(name: "Reverse Pec Deck", equipment: .machine,
                     primaryMuscles: [.rearDelt], category: .pull, difficulty: .beginner,
                     notes: "Arka deltoid için S tier; çoğu kişinin ihmal ettiği bölge."),
            Exercise(name: "Reverse Cable Crossover", equipment: .cable,
                     primaryMuscles: [.rearDelt], category: .pull, difficulty: .intermediate),
            Exercise(name: "Face Pull", equipment: .cable,
                     primaryMuscles: [.rearDelt], secondaryMuscles: [.traps],
                     category: .pull, difficulty: .beginner,
                     notes: "Arka deltoid + omuz sağlığı; dirsekleri yukarı çek."),
            Exercise(name: "Barbell Overhead Press", equipment: .barbell,
                     primaryMuscles: [.frontDelt], secondaryMuscles: [.triceps, .traps],
                     category: .push, difficulty: .intermediate),
            Exercise(name: "Oturarak Dumbbell Shoulder Press", equipment: .dumbbell,
                     primaryMuscles: [.frontDelt], secondaryMuscles: [.triceps],
                     category: .push, difficulty: .beginner),
            Exercise(name: "Machine Shoulder Press", equipment: .machine,
                     primaryMuscles: [.frontDelt], secondaryMuscles: [.triceps],
                     category: .push, difficulty: .beginner),
            Exercise(name: "Arnold Press", equipment: .dumbbell,
                     primaryMuscles: [.frontDelt], secondaryMuscles: [.triceps],
                     category: .push, difficulty: .intermediate),
            Exercise(name: "Upright Row", equipment: .barbell,
                     primaryMuscles: [.frontDelt, .traps], category: .push, difficulty: .intermediate),

            // MARK: Biceps (Pull)
            Exercise(name: "Bayesian Cable Curl", equipment: .cable,
                     primaryMuscles: [.biceps], category: .pull, difficulty: .intermediate,
                     notes: "Kol arkadayken gerili pozisyonu yükler (S+ tier)."),
            Exercise(name: "Dumbbell Preacher Curl", equipment: .dumbbell,
                     primaryMuscles: [.biceps], category: .pull, difficulty: .beginner),
            Exercise(name: "EZ Bar Curl", equipment: .barbell,
                     primaryMuscles: [.biceps], secondaryMuscles: [.forearmFront],
                     category: .pull, difficulty: .beginner),
            Exercise(name: "Ayakta Dumbbell Curl", equipment: .dumbbell,
                     primaryMuscles: [.biceps], category: .pull, difficulty: .beginner),
            Exercise(name: "Eğimli Dumbbell Curl", equipment: .dumbbell,
                     primaryMuscles: [.biceps], category: .pull, difficulty: .intermediate,
                     notes: "Eğimli bench'te kol geride → gerili pozisyon vurgusu."),
            Exercise(name: "Hammer Curl", equipment: .dumbbell,
                     primaryMuscles: [.biceps, .forearmFront], category: .pull, difficulty: .beginner),
            Exercise(name: "Barbell Curl", equipment: .barbell,
                     primaryMuscles: [.biceps], secondaryMuscles: [.forearmFront],
                     category: .pull, difficulty: .beginner),
            Exercise(name: "Cable Curl", equipment: .cable,
                     primaryMuscles: [.biceps], category: .pull, difficulty: .beginner),

            // MARK: Triceps (Push)
            Exercise(name: "Overhead Cable Triceps Extension", equipment: .cable,
                     primaryMuscles: [.triceps], category: .push, difficulty: .intermediate,
                     notes: "Uzun başı gerili pozisyonda yükler (S+ tier)."),
            Exercise(name: "Triceps Pushdown (Bar)", equipment: .cable,
                     primaryMuscles: [.triceps], category: .push, difficulty: .beginner),
            Exercise(name: "Triceps Pushdown (Halat)", equipment: .cable,
                     primaryMuscles: [.triceps], category: .push, difficulty: .beginner),
            Exercise(name: "Barbell Skullcrusher", equipment: .barbell,
                     primaryMuscles: [.triceps], category: .push, difficulty: .intermediate),
            Exercise(name: "Tek Kol Dumbbell Overhead Extension", equipment: .dumbbell,
                     primaryMuscles: [.triceps], category: .push, difficulty: .intermediate),
            Exercise(name: "Close-Grip Bench Press", equipment: .barbell,
                     primaryMuscles: [.triceps], secondaryMuscles: [.chest, .frontDelt],
                     category: .push, difficulty: .intermediate),
            Exercise(name: "Cable Triceps Kickback", equipment: .cable,
                     primaryMuscles: [.triceps], category: .push, difficulty: .beginner),
            Exercise(name: "Dar Tutuş Dips", equipment: .bodyweight,
                     primaryMuscles: [.triceps], secondaryMuscles: [.chest],
                     category: .push, difficulty: .intermediate),

            // MARK: Quadriceps (Bacak)
            Exercise(name: "Barbell Back Squat", equipment: .barbell,
                     primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings, .lowerBack],
                     category: .legs, difficulty: .intermediate,
                     notes: "Derin ROM kuadriseps büyümesini artırır. Sırtı nötr tut."),
            Exercise(name: "Hack Squat", equipment: .machine,
                     primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes],
                     category: .legs, difficulty: .intermediate,
                     notes: "Kuadriseps için S+ tier; stabil, derin çalışılabilir."),
            Exercise(name: "Pendulum Squat", equipment: .machine,
                     primaryMuscles: [.quadriceps, .glutes], category: .legs, difficulty: .advanced),
            Exercise(name: "Smith Machine Squat", equipment: .machine,
                     primaryMuscles: [.quadriceps, .glutes], category: .legs, difficulty: .beginner),
            Exercise(name: "Front Squat", equipment: .barbell,
                     primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes],
                     category: .legs, difficulty: .advanced),
            Exercise(name: "Leg Press (45°)", equipment: .machine,
                     primaryMuscles: [.quadriceps, .glutes], category: .legs, difficulty: .beginner),
            Exercise(name: "Leg Extension", equipment: .machine,
                     primaryMuscles: [.quadriceps], category: .legs, difficulty: .beginner,
                     notes: "İzolasyon; sistemik yorgunluk olmadan başarısızlığa yakın çalışılabilir."),
            Exercise(name: "Bulgarian Split Squat", equipment: .dumbbell,
                     primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings],
                     category: .legs, difficulty: .intermediate,
                     notes: "Tek bacak; denge + büyük ROM (S tier)."),
            Exercise(name: "Hamle (Lunge)", equipment: .dumbbell,
                     primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings],
                     category: .legs, difficulty: .beginner),
            Exercise(name: "Goblet Squat", equipment: .dumbbell,
                     primaryMuscles: [.quadriceps, .glutes], category: .legs, difficulty: .beginner),

            // MARK: Hamstring (Bacak)
            Exercise(name: "Oturarak Leg Curl", equipment: .machine,
                     primaryMuscles: [.hamstrings], category: .legs, difficulty: .beginner,
                     notes: "Oturarak versiyon gerili pozisyon sayesinde yatarak curl'den daha çok büyüme verir."),
            Exercise(name: "Yatarak Leg Curl", equipment: .machine,
                     primaryMuscles: [.hamstrings], category: .legs, difficulty: .beginner),
            Exercise(name: "Romanian Deadlift", equipment: .barbell,
                     primaryMuscles: [.hamstrings, .glutes], secondaryMuscles: [.lowerBack],
                     category: .legs, difficulty: .intermediate,
                     notes: "Kalçadan menteşelen, dizleri hafif bük; gerili pozisyonda hamstring yükü."),
            Exercise(name: "Stiff-Leg Deadlift", equipment: .barbell,
                     primaryMuscles: [.hamstrings, .glutes], secondaryMuscles: [.lowerBack],
                     category: .legs, difficulty: .intermediate),
            Exercise(name: "Nordic Curl", equipment: .bodyweight,
                     primaryMuscles: [.hamstrings], category: .legs, difficulty: .advanced),

            // MARK: Gluteus (Bacak)
            Exercise(name: "Barbell Hip Thrust", equipment: .barbell,
                     primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings],
                     category: .legs, difficulty: .intermediate),
            Exercise(name: "Machine Hip Thrust", equipment: .machine,
                     primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings],
                     category: .legs, difficulty: .beginner),
            Exercise(name: "Machine Hip Abduction", equipment: .machine,
                     primaryMuscles: [.glutes], category: .legs, difficulty: .beginner,
                     notes: "Gluteus medius için S tier izolasyon."),
            Exercise(name: "Cable Pull Through", equipment: .cable,
                     primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings],
                     category: .legs, difficulty: .beginner),
            Exercise(name: "45° Back Extension", equipment: .machine,
                     primaryMuscles: [.glutes, .hamstrings], secondaryMuscles: [.lowerBack],
                     category: .legs, difficulty: .beginner),
            Exercise(name: "Yürüyen Hamle", equipment: .dumbbell,
                     primaryMuscles: [.glutes, .quadriceps], secondaryMuscles: [.hamstrings],
                     category: .legs, difficulty: .beginner),
            Exercise(name: "Step Up", equipment: .dumbbell,
                     primaryMuscles: [.glutes, .quadriceps], category: .legs, difficulty: .beginner),

            // MARK: Baldır (Bacak)
            Exercise(name: "Ayakta Calf Raise", equipment: .machine,
                     primaryMuscles: [.calves], category: .legs, difficulty: .beginner,
                     notes: "Tepede sık, dipte tam ger. Rep aralığı büyüme için kritik değil."),
            Exercise(name: "Oturarak Calf Raise", equipment: .machine,
                     primaryMuscles: [.calves], category: .legs, difficulty: .beginner),
            Exercise(name: "Leg Press Calf Raise", equipment: .machine,
                     primaryMuscles: [.calves], category: .legs, difficulty: .beginner),

            // MARK: Karın / Core
            Exercise(name: "Asılı Bacak Kaldırma", equipment: .bodyweight,
                     primaryMuscles: [.lowerAbs], secondaryMuscles: [.upperAbs],
                     category: .core, difficulty: .intermediate),
            Exercise(name: "Cable Crunch", equipment: .cable,
                     primaryMuscles: [.upperAbs], category: .core, difficulty: .beginner,
                     notes: "Ağırlık eklenebildiği için karında progresif yüklemeye uygun."),
            Exercise(name: "Ağırlıklı Crunch", equipment: .bodyweight,
                     primaryMuscles: [.upperAbs], category: .core, difficulty: .beginner),
            Exercise(name: "Plank", equipment: .bodyweight,
                     primaryMuscles: [.upperAbs, .lowerAbs], secondaryMuscles: [.obliques],
                     category: .core, difficulty: .beginner),
            Exercise(name: "Bisiklet Crunch", equipment: .bodyweight,
                     primaryMuscles: [.obliques, .upperAbs], category: .core, difficulty: .beginner),
            Exercise(name: "Russian Twist", equipment: .bodyweight,
                     primaryMuscles: [.obliques], category: .core, difficulty: .beginner),
            Exercise(name: "Ab Wheel Rollout", equipment: .other,
                     primaryMuscles: [.upperAbs, .lowerAbs], secondaryMuscles: [.lowerBack],
                     category: .core, difficulty: .advanced),

            // MARK: Ön Kol
            Exercise(name: "Bilek Curl", equipment: .dumbbell,
                     primaryMuscles: [.forearmFront], category: .pull, difficulty: .beginner),
            Exercise(name: "Ters Bilek Curl", equipment: .dumbbell,
                     primaryMuscles: [.forearmBack], category: .pull, difficulty: .beginner),
            Exercise(name: "Ters Barbell Curl", equipment: .barbell,
                     primaryMuscles: [.forearmBack, .biceps], category: .pull, difficulty: .beginner)
        ]
        for exercise in list {
            exercise.imageURLsRaw = imageURLsRaw(for: exercise.name)
        }
        return list
    }

    // MARK: - Hazır Programlar

    /// Tek bir egzersiz bloğu. reps "5", "8-10", "AMRAP" gibi serbest metin.
    private static func ex(
        _ order: Int, _ name: String, _ sets: Int, _ reps: String,
        rest: Int, load: String? = nil, rir: String? = nil, notes: String? = nil
    ) -> TrainingBlock {
        TrainingBlock(
            order: order, type: .exercise, exerciseName: name,
            sets: sets, reps: reps, restSeconds: rest,
            load: load, rir: rir, notes: notes
        )
    }

    /// Hareket listesinden bir antrenman günü kurar (inverse ilişkileri bağlar).
    private static func day(_ number: Int, _ name: String, _ blocks: [TrainingBlock]) -> TrainingDay {
        let d = TrainingDay(dayNumber: number)
        d.name = name
        for block in blocks {
            block.day = d
            d.blocks.append(block)
        }
        return d
    }

    /// Dinlenme günü.
    private static func rest(_ number: Int) -> TrainingDay {
        let d = TrainingDay(dayNumber: number)
        d.isRestDay = true
        return d
    }

    /// Günlerden tek haftalık bir program kurar.
    private static func program(_ name: String, notes: String, days: [TrainingDay]) -> TrainingProgram {
        let p = TrainingProgram(name: name, notes: notes)
        let week = TrainingWeek(weekNumber: 1)
        week.program = p
        for d in days {
            d.week = week
            week.days.append(d)
        }
        p.weeks.append(week)
        return p
    }

    /// İnternetten derlenmiş, yaygın kullanılan 5 antrenman programı.
    static var defaultPrograms: [TrainingProgram] {
        [stronglifts5x5, pushPullLegs, phul, upperLower, nSuns531]
    }

    // 1) StrongLifts 5×5 — Başlangıç · Güç · 3 gün (A/B dönüşümlü)
    private static var stronglifts5x5: TrainingProgram {
        program(
            "StrongLifts 5×5",
            notes: "Başlangıç güç programı. A/B günleri dönüşümlü, haftada 3 antrenman. 5×5'i tamamladığın hareketin ağırlığını bir sonraki seansta artır.",
            days: [
                day(1, "A: Squat / Bench / Row", [
                    ex(0, "Barbell Back Squat", 5, "5", rest: 180),
                    ex(1, "Bench Press", 5, "5", rest: 180),
                    ex(2, "Barbell Row", 5, "5", rest: 180)
                ]),
                rest(2),
                day(3, "B: Squat / OHP / Deadlift", [
                    ex(0, "Barbell Back Squat", 5, "5", rest: 180),
                    ex(1, "Barbell Overhead Press", 5, "5", rest: 180),
                    ex(2, "Deadlift", 1, "5", rest: 180)
                ]),
                rest(4),
                day(5, "A: Squat / Bench / Row", [
                    ex(0, "Barbell Back Squat", 5, "5", rest: 180),
                    ex(1, "Bench Press", 5, "5", rest: 180),
                    ex(2, "Barbell Row", 5, "5", rest: 180)
                ]),
                rest(6),
                rest(7)
            ]
        )
    }

    // 2) Push / Pull / Legs — Orta · Hipertrofi · 6 gün (2 tur)
    private static var pushPullLegs: TrainingProgram {
        program(
            "Push / Pull / Legs",
            notes: "Haftada 6 gün, itiş/çekiş/bacak iki tur döner. Çoğu set 8–12 tekrar; son tekrarda 1–2 yedek (RIR) bırak.",
            days: [
                day(1, "Push A", [
                    ex(0, "Bench Press", 4, "6-8", rest: 150, rir: "1-2"),
                    ex(1, "Oturarak Dumbbell Shoulder Press", 3, "8-10", rest: 120),
                    ex(2, "Eğimli Dumbbell Press", 3, "10-12", rest: 90),
                    ex(3, "Dumbbell Lateral Raise", 3, "12-15", rest: 60),
                    ex(4, "Triceps Pushdown (Halat)", 3, "10-12", rest: 60),
                    ex(5, "Overhead Cable Triceps Extension", 3, "10-12", rest: 60)
                ]),
                day(2, "Pull A", [
                    ex(0, "Deadlift", 3, "5", rest: 180),
                    ex(1, "Barfiks (Geniş Tutuş)", 3, "8-10", rest: 120),
                    ex(2, "Oturarak Cable Row", 3, "10-12", rest: 90),
                    ex(3, "Face Pull", 3, "15", rest: 60),
                    ex(4, "Barbell Curl", 3, "8-10", rest: 60),
                    ex(5, "Hammer Curl", 3, "10-12", rest: 60)
                ]),
                day(3, "Legs A", [
                    ex(0, "Barbell Back Squat", 4, "6-8", rest: 180, rir: "1-2"),
                    ex(1, "Romanian Deadlift", 3, "8-10", rest: 120),
                    ex(2, "Leg Press (45°)", 3, "10-12", rest: 90),
                    ex(3, "Oturarak Leg Curl", 3, "10-12", rest: 60),
                    ex(4, "Ayakta Calf Raise", 4, "12-15", rest: 60)
                ]),
                day(4, "Push B", [
                    ex(0, "Barbell Overhead Press", 4, "6-8", rest: 150, rir: "1-2"),
                    ex(1, "Eğimli Bench Press", 3, "8-10", rest: 120),
                    ex(2, "Machine Chest Press", 3, "10-12", rest: 90),
                    ex(3, "Cable Lateral Raise", 3, "12-15", rest: 60),
                    ex(4, "Close-Grip Bench Press", 3, "8-10", rest: 90),
                    ex(5, "Triceps Pushdown (Bar)", 3, "10-12", rest: 60)
                ]),
                day(5, "Pull B", [
                    ex(0, "Barbell Row", 4, "6-8", rest: 150, rir: "1-2"),
                    ex(1, "Lat Pulldown (Geniş Tutuş)", 3, "10-12", rest: 90),
                    ex(2, "Tek Kol Dumbbell Row", 3, "10-12", rest: 90),
                    ex(3, "Reverse Pec Deck", 3, "15", rest: 60),
                    ex(4, "EZ Bar Curl", 3, "8-10", rest: 60),
                    ex(5, "Bayesian Cable Curl", 3, "10-12", rest: 60)
                ]),
                day(6, "Legs B", [
                    ex(0, "Front Squat", 4, "6-8", rest: 180, rir: "1-2"),
                    ex(1, "Bulgarian Split Squat", 3, "8-10", rest: 120),
                    ex(2, "Leg Extension", 3, "12-15", rest: 60),
                    ex(3, "Yatarak Leg Curl", 3, "10-12", rest: 60),
                    ex(4, "Oturarak Calf Raise", 4, "15-20", rest: 60)
                ]),
                rest(7)
            ]
        )
    }

    // 3) PHUL — Orta · Güç + Hipertrofi · 4 gün
    private static var phul: TrainingProgram {
        program(
            "PHUL (Power Hypertrophy Upper Lower)",
            notes: "2 güç günü (3–5 tekrar, ağır) + 2 hipertrofi günü (8–15 tekrar). Üst/alt vücut ayrımıyla güç ve kası birlikte geliştirir.",
            days: [
                day(1, "Upper Power", [
                    ex(0, "Bench Press", 4, "3-5", rest: 180, rir: "1"),
                    ex(1, "Barbell Row", 4, "3-5", rest: 180, rir: "1"),
                    ex(2, "Barbell Overhead Press", 3, "5-8", rest: 150),
                    ex(3, "Lat Pulldown (Geniş Tutuş)", 3, "6-10", rest: 90),
                    ex(4, "Barbell Curl", 3, "6-10", rest: 60),
                    ex(5, "Close-Grip Bench Press", 3, "6-10", rest: 90)
                ]),
                day(2, "Lower Power", [
                    ex(0, "Barbell Back Squat", 4, "3-5", rest: 180, rir: "1"),
                    ex(1, "Deadlift", 3, "3-5", rest: 180, rir: "1"),
                    ex(2, "Leg Press (45°)", 4, "10-15", rest: 120),
                    ex(3, "Oturarak Leg Curl", 4, "6-10", rest: 90),
                    ex(4, "Ayakta Calf Raise", 4, "6-10", rest: 60)
                ]),
                rest(3),
                day(4, "Upper Hypertrophy", [
                    ex(0, "Eğimli Bench Press", 4, "8-12", rest: 90, rir: "1-2"),
                    ex(1, "Oturarak Cable Row", 4, "8-12", rest: 90),
                    ex(2, "Machine Chest Press", 3, "10-15", rest: 75),
                    ex(3, "Dumbbell Lateral Raise", 4, "12-15", rest: 60),
                    ex(4, "Eğimli Dumbbell Curl", 4, "10-15", rest: 60),
                    ex(5, "Triceps Pushdown (Halat)", 4, "10-15", rest: 60)
                ]),
                day(5, "Lower Hypertrophy", [
                    ex(0, "Front Squat", 4, "8-12", rest: 120, rir: "1-2"),
                    ex(1, "Romanian Deadlift", 4, "8-12", rest: 90),
                    ex(2, "Leg Extension", 4, "12-15", rest: 60),
                    ex(3, "Yatarak Leg Curl", 4, "12-15", rest: 60),
                    ex(4, "Oturarak Calf Raise", 4, "12-15", rest: 60)
                ]),
                rest(6),
                rest(7)
            ]
        )
    }

    // 4) Upper / Lower — Orta · Genel · 4 gün
    private static var upperLower: TrainingProgram {
        program(
            "Upper / Lower Split",
            notes: "Üst/alt vücut dönüşümlü, haftada 4 antrenman. Güç ve kas için dengeli 6–12 tekrar aralığı.",
            days: [
                day(1, "Upper A", [
                    ex(0, "Bench Press", 4, "6-8", rest: 150, rir: "1-2"),
                    ex(1, "Barbell Row", 4, "6-8", rest: 150, rir: "1-2"),
                    ex(2, "Oturarak Dumbbell Shoulder Press", 3, "8-10", rest: 90),
                    ex(3, "Lat Pulldown (Geniş Tutuş)", 3, "8-10", rest: 90),
                    ex(4, "Barbell Curl", 3, "10-12", rest: 60),
                    ex(5, "Triceps Pushdown (Halat)", 3, "10-12", rest: 60)
                ]),
                day(2, "Lower A", [
                    ex(0, "Barbell Back Squat", 4, "6-8", rest: 180, rir: "1-2"),
                    ex(1, "Romanian Deadlift", 3, "8-10", rest: 120),
                    ex(2, "Leg Press (45°)", 3, "10-12", rest: 90),
                    ex(3, "Oturarak Leg Curl", 3, "10-12", rest: 60),
                    ex(4, "Ayakta Calf Raise", 4, "12-15", rest: 60)
                ]),
                rest(3),
                day(4, "Upper B", [
                    ex(0, "Eğimli Bench Press", 4, "8-10", rest: 120, rir: "1-2"),
                    ex(1, "Chin-up", 3, "8-10", rest: 120),
                    ex(2, "Arnold Press", 3, "10-12", rest: 90),
                    ex(3, "Oturarak Cable Row", 3, "10-12", rest: 90),
                    ex(4, "Hammer Curl", 3, "12", rest: 60),
                    ex(5, "Overhead Cable Triceps Extension", 3, "12", rest: 60)
                ]),
                day(5, "Lower B", [
                    ex(0, "Deadlift", 4, "5", rest: 180, rir: "1-2"),
                    ex(1, "Bulgarian Split Squat", 3, "8-10", rest: 120),
                    ex(2, "Leg Extension", 3, "12-15", rest: 60),
                    ex(3, "Yatarak Leg Curl", 3, "12", rest: 60),
                    ex(4, "Oturarak Calf Raise", 4, "15", rest: 60)
                ]),
                rest(6),
                rest(7)
            ]
        )
    }

    // 5) nSuns 5/3/1 — Orta · Güç · 4 gün
    private static var nSuns531: TrainingProgram {
        program(
            "nSuns 5/3/1",
            notes: "Wendler 5/3/1 temelli, yüksek hacimli güç programı. Ana kaldırış 8–9 set, yük antrenman maksimuna (TM) göre %65→%95 piramitlenir; son sette mümkün olduğunca çok tekrar (AMRAP). TM'yi her hafta artır.",
            days: [
                day(1, "Bench Day", [
                    ex(0, "Bench Press", 8, "5/3/1+", rest: 180, load: "TM %65→95", notes: "8 set: %65×8, %75×6, %85×4, %85×4, %85×3, %80×5, %75×6, %70×7"),
                    ex(1, "Barbell Overhead Press", 8, "6", rest: 120, load: "TM %50→80"),
                    ex(2, "Triceps Pushdown (Halat)", 3, "12", rest: 60),
                    ex(3, "Barbell Curl", 3, "12", rest: 60)
                ]),
                day(2, "Squat Day", [
                    ex(0, "Barbell Back Squat", 8, "5/3/1+", rest: 180, load: "TM %65→95", notes: "Ana kaldırış piramidi"),
                    ex(1, "Romanian Deadlift", 8, "5", rest: 150, load: "TM %50→80"),
                    ex(2, "Leg Press (45°)", 3, "12", rest: 90),
                    ex(3, "Ayakta Calf Raise", 3, "15", rest: 60)
                ]),
                rest(3),
                day(4, "OHP Day", [
                    ex(0, "Barbell Overhead Press", 8, "5/3/1+", rest: 180, load: "TM %65→95", notes: "Ana kaldırış piramidi"),
                    ex(1, "Bench Press", 8, "5", rest: 150, load: "TM %50→80"),
                    ex(2, "Dumbbell Lateral Raise", 3, "15", rest: 60),
                    ex(3, "Face Pull", 3, "15", rest: 60)
                ]),
                day(5, "Deadlift Day", [
                    ex(0, "Deadlift", 8, "5/3/1+", rest: 210, load: "TM %65→95", notes: "Ana kaldırış piramidi"),
                    ex(1, "Barbell Back Squat", 8, "5", rest: 150, load: "TM %50→80"),
                    ex(2, "Oturarak Leg Curl", 3, "12", rest: 60),
                    ex(3, "Cable Crunch", 3, "15", rest: 60)
                ]),
                rest(6),
                rest(7)
            ]
        )
    }
}
