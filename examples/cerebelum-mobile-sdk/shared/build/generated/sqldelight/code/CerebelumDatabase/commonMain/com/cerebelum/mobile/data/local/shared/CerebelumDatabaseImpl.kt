package com.cerebelum.mobile.`data`.local.shared

import app.cash.sqldelight.TransacterImpl
import app.cash.sqldelight.db.AfterVersion
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlSchema
import com.cerebelum.mobile.`data`.local.CerebelumDatabase
import com.cerebelum.mobile.`data`.local.CerebelumDatabaseQueries
import kotlin.Long
import kotlin.Unit
import kotlin.reflect.KClass

internal val KClass<CerebelumDatabase>.schema: SqlSchema<QueryResult.Value<Unit>>
  get() = CerebelumDatabaseImpl.Schema

internal fun KClass<CerebelumDatabase>.newInstance(driver: SqlDriver): CerebelumDatabase =
    CerebelumDatabaseImpl(driver)

private class CerebelumDatabaseImpl(
  driver: SqlDriver,
) : TransacterImpl(driver), CerebelumDatabase {
  override val cerebelumDatabaseQueries: CerebelumDatabaseQueries = CerebelumDatabaseQueries(driver)

  public object Schema : SqlSchema<QueryResult.Value<Unit>> {
    override val version: Long
      get() = 1

    override fun create(driver: SqlDriver): QueryResult.Value<Unit> {
      driver.execute(null, """
          |CREATE TABLE TaskEntity (
          |    id TEXT NOT NULL PRIMARY KEY,
          |    type TEXT NOT NULL,
          |    payload TEXT NOT NULL, -- JSON string
          |    status TEXT NOT NULL,
          |    sync_status TEXT NOT NULL,
          |    created_at INTEGER NOT NULL,
          |    completed_at INTEGER,
          |    result TEXT
          |)
          """.trimMargin(), 0)
      driver.execute(null, """
          |CREATE TABLE SyncAttemptEntity (
          |    id TEXT NOT NULL PRIMARY KEY,
          |    task_id TEXT NOT NULL,
          |    attempt_time INTEGER NOT NULL,
          |    error_message TEXT,
          |    retry_count INTEGER NOT NULL DEFAULT 0,
          |    FOREIGN KEY(task_id) REFERENCES TaskEntity(id)
          |)
          """.trimMargin(), 0)
      return QueryResult.Unit
    }

    override fun migrate(
      driver: SqlDriver,
      oldVersion: Long,
      newVersion: Long,
      vararg callbacks: AfterVersion,
    ): QueryResult.Value<Unit> = QueryResult.Unit
  }
}
