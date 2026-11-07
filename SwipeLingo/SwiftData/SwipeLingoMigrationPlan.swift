import SwiftData

// MARK: - SchemaV1
//
// Первая отслеживаемая версия схемы — точка отсчёта, а не "версия 1 из многих":
// до этого момента схема вообще не версионировалась (ModelContainerFactory при
// несовпадении просто удалял и пересоздавал локальный стор, см. её fallback).
// У проекта пока нет production-пользователей, поэтому реконструировать более
// раннюю историю схемы не нужно — начиная с этой версии, изменения схемы идут
// через настоящие MigrationStage, без потери локальных данных пользователя.
//
// Список моделей — единственный источник правды для состава схемы; используется
// и здесь, и в ModelContainerFactory (через Schema(versionedSchema: SchemaV1.self)) —
// не дублируется.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Card.self,
            CardSet.self,
            Collection.self,
            Pile.self,
            PairsSet.self,
            PairsPile.self,
            UserProfile.self,
            Book.self,
            BookProgress.self,
            BookBookmark.self,
            AppSyncState.self
        ]
    }
}

// MARK: - SchemaV2
//
// + `StudyDay` — история занятий по дням для Statistics, серии дней, виджета и напоминаний
// (2026-11-05). Остальные модели не менялись. Переход V1 → V2 — лёгкая миграция: новая сущность,
// существующие данные не трогаются.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [StudyDay.self]
    }
}

/// Текущая версия схемы — её открывает `ModelContainerFactory`. При следующем изменении схемы
/// переключить на новую версию здесь, а не в фабрике.
typealias CurrentSchema = SchemaV2

// MARK: - SwipeLingoMigrationPlan
//
// Единая точка регистрации версий схемы и переходов между ними.
//
// Паттерн для следующего изменения схемы:
// 1. Завести SchemaV2 (новый enum: VersionedSchema, versionIdentifier на минор
//    выше, models — со сформировавшимся изменением).
// 2. Добавить SchemaV2.self в `schemas` ниже.
// 3. Добавить в `stages` переход: `.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`
//    для совместимых изменений (новое поле с default-значением — как было с
//    `UserProfile.updatedAt`), либо `.custom(...)` с явной трансформацией данных
//    для несовместимых изменений (переименование/смена типа поля и т.п.).

enum SwipeLingoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
