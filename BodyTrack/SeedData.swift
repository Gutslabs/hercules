import Foundation
import SwiftData

enum DemoSeed {
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

        try? ctx.save()
    }
}
