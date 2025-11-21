package com.cerebelum.mobile.`data`.local

import app.cash.sqldelight.Query
import app.cash.sqldelight.TransacterImpl
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlCursor
import app.cash.sqldelight.db.SqlDriver
import kotlin.Any
import kotlin.Long
import kotlin.String

public class CerebelumDatabaseQueries(
  driver: SqlDriver,
) : TransacterImpl(driver) {
  public fun <T : Any> selectAllTasks(mapper: (
    id: String,
    type: String,
    payload: String,
    status: String,
    sync_status: String,
    created_at: Long,
    completed_at: Long?,
    result: String?,
  ) -> T): Query<T> = Query(-1_538_413_720, arrayOf("TaskEntity"), driver, "CerebelumDatabase.sq",
      "selectAllTasks", "SELECT * FROM TaskEntity") { cursor ->
    mapper(
      cursor.getString(0)!!,
      cursor.getString(1)!!,
      cursor.getString(2)!!,
      cursor.getString(3)!!,
      cursor.getString(4)!!,
      cursor.getLong(5)!!,
      cursor.getLong(6),
      cursor.getString(7)
    )
  }

  public fun selectAllTasks(): Query<TaskEntity> = selectAllTasks { id, type, payload, status,
      sync_status, created_at, completed_at, result ->
    TaskEntity(
      id,
      type,
      payload,
      status,
      sync_status,
      created_at,
      completed_at,
      result
    )
  }

  public fun <T : Any> selectPendingSyncTasks(mapper: (
    id: String,
    type: String,
    payload: String,
    status: String,
    sync_status: String,
    created_at: Long,
    completed_at: Long?,
    result: String?,
  ) -> T): Query<T> = Query(-449_651_753, arrayOf("TaskEntity"), driver, "CerebelumDatabase.sq",
      "selectPendingSyncTasks",
      "SELECT * FROM TaskEntity WHERE sync_status = 'NOT_SYNCED' OR sync_status = 'FAILED'") {
      cursor ->
    mapper(
      cursor.getString(0)!!,
      cursor.getString(1)!!,
      cursor.getString(2)!!,
      cursor.getString(3)!!,
      cursor.getString(4)!!,
      cursor.getLong(5)!!,
      cursor.getLong(6),
      cursor.getString(7)
    )
  }

  public fun selectPendingSyncTasks(): Query<TaskEntity> = selectPendingSyncTasks { id, type,
      payload, status, sync_status, created_at, completed_at, result ->
    TaskEntity(
      id,
      type,
      payload,
      status,
      sync_status,
      created_at,
      completed_at,
      result
    )
  }

  public fun <T : Any> selectTaskById(id: String, mapper: (
    id: String,
    type: String,
    payload: String,
    status: String,
    sync_status: String,
    created_at: Long,
    completed_at: Long?,
    result: String?,
  ) -> T): Query<T> = SelectTaskByIdQuery(id) { cursor ->
    mapper(
      cursor.getString(0)!!,
      cursor.getString(1)!!,
      cursor.getString(2)!!,
      cursor.getString(3)!!,
      cursor.getString(4)!!,
      cursor.getLong(5)!!,
      cursor.getLong(6),
      cursor.getString(7)
    )
  }

  public fun selectTaskById(id: String): Query<TaskEntity> = selectTaskById(id) { id_, type,
      payload, status, sync_status, created_at, completed_at, result ->
    TaskEntity(
      id_,
      type,
      payload,
      status,
      sync_status,
      created_at,
      completed_at,
      result
    )
  }

  public fun insertTask(
    id: String,
    type: String,
    payload: String,
    status: String,
    sync_status: String,
    created_at: Long,
  ) {
    driver.execute(-1_819_930_819, """
        |INSERT OR REPLACE INTO TaskEntity(id, type, payload, status, sync_status, created_at)
        |VALUES (?, ?, ?, ?, ?, ?)
        """.trimMargin(), 6) {
          bindString(0, id)
          bindString(1, type)
          bindString(2, payload)
          bindString(3, status)
          bindString(4, sync_status)
          bindLong(5, created_at)
        }
    notifyQueries(-1_819_930_819) { emit ->
      emit("TaskEntity")
    }
  }

  public fun updateTaskStatus(
    status: String,
    completed_at: Long?,
    result: String?,
    id: String,
  ) {
    driver.execute(-1_442_002_017,
        """UPDATE TaskEntity SET status = ?, completed_at = ?, result = ?, sync_status = 'NOT_SYNCED' WHERE id = ?""",
        4) {
          bindString(0, status)
          bindLong(1, completed_at)
          bindString(2, result)
          bindString(3, id)
        }
    notifyQueries(-1_442_002_017) { emit ->
      emit("TaskEntity")
    }
  }

  public fun updateSyncStatus(sync_status: String, id: String) {
    driver.execute(-308_934_603, """UPDATE TaskEntity SET sync_status = ? WHERE id = ?""", 2) {
          bindString(0, sync_status)
          bindString(1, id)
        }
    notifyQueries(-308_934_603) { emit ->
      emit("TaskEntity")
    }
  }

  private inner class SelectTaskByIdQuery<out T : Any>(
    public val id: String,
    mapper: (SqlCursor) -> T,
  ) : Query<T>(mapper) {
    override fun addListener(listener: Query.Listener) {
      driver.addListener("TaskEntity", listener = listener)
    }

    override fun removeListener(listener: Query.Listener) {
      driver.removeListener("TaskEntity", listener = listener)
    }

    override fun <R> execute(mapper: (SqlCursor) -> QueryResult<R>): QueryResult<R> =
        driver.executeQuery(558_331_890, """SELECT * FROM TaskEntity WHERE id = ?""", mapper, 1) {
      bindString(0, id)
    }

    override fun toString(): String = "CerebelumDatabase.sq:selectTaskById"
  }
}
