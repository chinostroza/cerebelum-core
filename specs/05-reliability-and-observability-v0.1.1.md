# Design Document - Reliability & Observability (v0.1.1)

**Module:** cerebelum-core
**Target Version:** 0.1.1
**Status:** Draft

## Overview

This document outlines the reliability and observability improvements scheduled for v0.1.1.

## 1. EventStore Reliability

### Problem
Current `flush_batch` implementation lacks retry logic. Transient database failures can cause data loss or process crashes without recovery attempts.

### Solution
Implement exponential backoff retry logic in `EventStore.flush_batch/1`.

- **Retry Strategy:** 3 attempts with exponential backoff (e.g., 100ms, 200ms, 400ms).
- **Failure Handling:** If retries are exhausted, crash the process to trigger supervision recovery (letting the supervisor restart the EventStore).

## 2. Serialization Standardization

### Problem
Custom serialization logic is brittle and may not handle all edge cases (e.g., Date/Time structs) consistently for JSONB storage.

### Solution
Standardize on `Jason` for serialization.

- Use `Jason.encode!` or explicit `prepare_for_json` helper to ensure all types are JSON-safe before passing to Ecto.

## 3. Observability (Telemetry)

### Problem
Lack of visibility into workflow lifecycle and EventStore performance.

### Solution
Add `:telemetry` events:

- `[:cerebelum, :workflow, :start]` - When a workflow starts.
- `[:cerebelum, :workflow, :stop]` - When a workflow terminates.
- `[:cerebelum, :event_store, :flush]` - When events are flushed to DB (measure duration and count).
