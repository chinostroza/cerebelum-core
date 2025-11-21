package com.cerebelum.mobile.`data`.local

import kotlin.Long
import kotlin.String

public data class TaskEntity(
  public val id: String,
  public val type: String,
  public val payload: String,
  public val status: String,
  public val sync_status: String,
  public val created_at: Long,
  public val completed_at: Long?,
  public val result: String?,
)
