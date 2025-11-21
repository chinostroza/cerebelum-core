package com.cerebelum.mobile.`data`.local

import app.cash.sqldelight.Transacter
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlSchema
import com.cerebelum.mobile.`data`.local.shared.newInstance
import com.cerebelum.mobile.`data`.local.shared.schema
import kotlin.Unit

public interface CerebelumDatabase : Transacter {
  public val cerebelumDatabaseQueries: CerebelumDatabaseQueries

  public companion object {
    public val Schema: SqlSchema<QueryResult.Value<Unit>>
      get() = CerebelumDatabase::class.schema

    public operator fun invoke(driver: SqlDriver): CerebelumDatabase =
        CerebelumDatabase::class.newInstance(driver)
  }
}
