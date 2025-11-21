package com.cerebelum.mobile.`data`.local

import kotlin.Long
import kotlin.String

public data class SyncAttemptEntity(
  public val id: String,
  public val task_id: String,
  public val attempt_time: Long,
  public val error_message: String?,
  public val retry_count: Long,
)
