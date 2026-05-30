import XCTest
import SwiftData
@testable import BodyTrack

// MARK: - Test target kurulumu
//
// Bu dosya hazır testleri içerir ama henüz bir test TARGET'ına bağlı değil.
// Xcode'da tek tıkla ekleyin (pbxproj'u elle düzenlemek projeyi bozma riski taşır):
//   File > New > Target… > Unit Testing Bundle  (host app: BodyTrack)
// Sonra bu dosyayı oluşan BodyTrackTests target'ına dahil edin. Testler:
//   ChatActionExecutor (LLM aksiyon motoru), EmbeddingMath, WorkoutSession accessors.

// MARK: - ChatActionExecutor (en riskli kod: LLM çıktısına göre veri yazımı)

@MainActor
final class ChatActionExecutorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Measurement.self, UserProfile.self, Recipe.self, FoodEntry.self,
            FoodPreset.self, WorkoutSession.self, WorkoutTemplateExercise.self,
            WorkoutProgramArchive.self, WorkoutPlanOverride.self, StepEntry.self,
            MonthlyGoal.self, WorkoutLog.self, WorkoutExerciseEntry.self, ExerciseSet.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func testLogFoodInsertsEntry() throws {
        let ctx = try makeContext()
        var action = AIAppAction(tool: .logFood)
        action.name = "Tavuk göğsü"
        action.calories = 250
        action.proteinG = 45

        let result = try ChatActionExecutor.executeAction(action, ctx: ctx)

        let foods = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods.first?.calories, 250)
        XCTAssertTrue(result.contains("Tavuk göğsü"))
    }

    func testLogFoodWithoutCaloriesThrows() throws {
        let ctx = try makeContext()
        var action = AIAppAction(tool: .logFood)
        action.name = "Bilinmeyen"
        // calories yok
        XCTAssertThrowsError(try ChatActionExecutor.executeAction(action, ctx: ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).count, 0)
    }

    func testAddRecipeWithoutSourceURLRejected() throws {
        let ctx = try makeContext()
        var action = AIAppAction(tool: .addRecipe)
        action.title = "Kaynaksız tarif"
        action.ingredients = "x"
        action.instructions = "y"
        // url / sourceURL yok → kaynaksız tarif eklenmemeli
        XCTAssertThrowsError(try ChatActionExecutor.executeAction(action, ctx: ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Recipe>()).count, 0)
    }

    func testAddExerciseCreatesSession() throws {
        let ctx = try makeContext()
        var action = AIAppAction(tool: .updateWorkoutPlan)
        action.workoutOperation = "add_exercise"
        action.weekday = 2
        action.exerciseName = "Bench Press"
        action.sets = 4
        action.reps = "8-10"

        _ = try ChatActionExecutor.executeAction(action, ctx: ctx)

        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.first?.weekday, 2)
        XCTAssertTrue(sessions.first?.templateExercises.contains(where: { $0.name == "Bench Press" }) ?? false)
    }
}

// MARK: - EmbeddingMath.cosine

final class EmbeddingMathTests: XCTestCase {
    func testIdenticalVectorsCosineIsOne() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(EmbeddingMath.cosine(v, v), 1.0, accuracy: 1e-5)
    }

    func testOrthogonalVectorsCosineIsZero() {
        XCTAssertEqual(EmbeddingMath.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-5)
    }

    func testMismatchedOrEmptyDimensionsReturnZero() {
        XCTAssertEqual(EmbeddingMath.cosine([1, 2, 3], []), 0.0)
        XCTAssertEqual(EmbeddingMath.cosine([1, 2, 3], [1, 2]), 0.0)
    }
}

// MARK: - WorkoutSession bounds-safe weekday accessors (decoded/corrupt veri çökmesin)

final class WorkoutSessionWeekdayTests: XCTestCase {
    func testValidWeekdayNames() {
        XCTAssertEqual(WorkoutSession.weekdayName(1), "Pazar")
        XCTAssertEqual(WorkoutSession.weekdayName(7), "Cumartesi")
        XCTAssertEqual(WorkoutSession.weekdayShortName(2), "Pt")
    }

    func testOutOfRangeWeekdayReturnsPlaceholderNotCrash() {
        XCTAssertEqual(WorkoutSession.weekdayName(99), "?")
        XCTAssertEqual(WorkoutSession.weekdayName(-1), "?")
        XCTAssertEqual(WorkoutSession.weekdayShortName(8), "?")
        XCTAssertEqual(WorkoutSession.weekdayShortName(Int.max), "?")
    }
}
