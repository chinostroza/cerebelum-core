# Business Rules and Validation

Complete reference for all business rules, validation constraints, and operational policies in OpenSpecification.

## Table of Contents
1. [Workflow Rules](#workflow-rules)
2. [Input Validation](#input-validation)
3. [Token Management](#token-management)
4. [Storage and Persistence](#storage-and-persistence)
5. [Security Rules](#security-rules)
6. [Error Handling](#error-handling)

---

## Workflow Rules

### Rule 1: Sequential Phase Progression

**Description:** Phases must be completed in strict sequential order.

**Order:** Requirements → Design → Tasks → Complete

**Enforcement:**
```typescript
const phases = ['requirements', 'design', 'tasks', 'complete']
const currentIndex = phases.indexOf(state.phase)
const nextPhase = phases[currentIndex + 1] || null
const previousPhase = phases[currentIndex - 1] || null

// Cannot skip phases
if (requestedPhase !== nextPhase) {
  throw new Error('Cannot skip phases')
}
```

**Business Logic:**
- User cannot jump from Requirements to Tasks
- User cannot go back after approving (one-way progression)
- Each phase must be completed before next begins

**Why:** Each phase builds upon and refines the previous phase. Skipping creates inconsistent specifications.

### Rule 2: Approval Gates

**Description:** Each phase requires explicit user approval before proceeding.

**States:**
```typescript
interface ApprovalState {
  requirements: boolean  // false = pending, true = approved
  design: boolean
  tasks: boolean
}
```

**Transition Condition:**
```typescript
canProceedToNext = Boolean(
  nextPhase &&                         // Has next phase
  state.approvals[state.phase] === true &&  // Current phase approved
  !state.isGenerating                   // Not currently generating
)
```

**Business Logic:**
- No automatic phase progression without explicit approval
- Cannot approve while generation is in progress
- Approval is persistent (survives page refresh)
- Approval cannot be revoked after phase change

**Why:** Ensures user reviews and validates content before it becomes input for next phase.

### Rule 3: Generation Lock

**Description:** Once Requirements are generated, cannot modify input parameters.

**Locked Parameters:**
- Feature description
- Context files
- Selected AI model
- API key (can be changed but resets workflow)

**UI Enforcement:**
```typescript
useEffect(() => {
  if (state.requirements && state.requirements.trim().length > 0) {
    setCurrentStep(4)  // Force to workflow step
    disableInputs(true)
  }
}, [state.requirements])
```

**Business Logic:**
- Input fields become read-only
- Model selector is disabled
- Can only reset entire workflow to change inputs
- "Reset & Start Fresh" button becomes primary action

**Why:** Prevents generating Design/Tasks based on different inputs than Requirements, maintaining consistency.

### Rule 4: Prompt Change Detection

**Description:** Automatically reset workflow if user significantly changes description during Requirements phase.

**Detection Algorithm:**
```typescript
function hasPromptChanged(stored, new, storedName, newName): boolean {
  // Extract keywords (words > 3 characters)
  const storedWords = extractKeywords(stored + storedName)
  const newWords = extractKeywords(new + newName)

  // Calculate word overlap
  const overlap = intersection(storedWords, newWords).length /
                  max(storedWords.length, newWords.length)

  // < 40% overlap = significant change
  return overlap < 0.4
}
```

**Threshold:** 40% word overlap minimum

**Examples:**
```
Stored: "Build user authentication system"
New:    "Build user authentication with password recovery"
Overlap: 75% → No reset

Stored: "Build authentication system"
New:    "Create e-commerce shopping cart"
Overlap: 0% → Auto-reset
```

**Business Logic:**
- Only checked during Requirements phase
- Triggered before generating Requirements
- Silently resets all previous content
- User is NOT prompted (automatic)

**Why:** Prevents generating specifications for a different feature than originally described.

---

## Input Validation

### Rule 5: API Key Validation

**Description:** OpenRouter API key must be valid before any generation.

**Format:** `sk-or-v1-{64 alphanumeric characters}`

**Validation:**
```typescript
// Format check (client)
const isValidFormat = /^sk-or-v1-[a-zA-Z0-9]{64}$/.test(apiKey)

// Functional check (server)
async function validateApiKey(apiKey: string): Promise<boolean> {
  try {
    const client = new OpenRouterClient(apiKey)
    await client.listModels()
    return true
  } catch {
    return false
  }
}
```

**Business Logic:**
- Validated on entry (before storing)
- Validated before each generation
- Stored in sessionStorage (cleared on browser close)
- Never logged or exposed in errors
- Invalid key prevents all generation attempts

**Error Messages:**
- Format invalid: "Invalid API key format. Expected: sk-or-v1-..."
- Authentication failed: "API key is invalid or expired"
- Network error: "Could not validate API key. Check your connection."

### Rule 6: Model Selection

**Description:** User must select an AI model before generation.

**Requirements:**
- Model must be from fetched model list
- Model must support required context length (32,768 tokens)
- Model pricing information must be available

**Validation:**
```typescript
const hasValidModel = Boolean(
  selectedModel &&
  selectedModel.id &&
  selectedModel.context_length >= 32768
)
```

**Business Logic:**
- Models are fetched from OpenRouter API
- Models with insufficient context are filtered out
- Free models are marked with special badge
- Pricing is displayed per model
- Selection persists in sessionStorage

### Rule 7: Feature Description

**Description:** User must provide meaningful feature description.

**Requirements:**
- Minimum length: 10 characters
- Maximum length: 5,000 characters (~1,250 tokens)
- Cannot be only whitespace

**Validation:**
```typescript
const description = userInput.trim()
const isValid = description.length >= 10 && description.length <= 5000

if (description.length > 5000) {
  // Auto-truncate with warning
  description = description.substring(0, 5000)
  showWarning('Description truncated to 5,000 characters')
}
```

**Business Logic:**
- Validation on input change
- Character counter displayed
- Truncation happens automatically
- Truncated content appends: "[Description truncated to fit token limits]"

### Rule 8: Context Files

**Description:** Optional files that provide additional context for Requirements generation.

**Constraints:**

| Constraint | Limit | Enforcement |
|------------|-------|-------------|
| File size (individual) | 2KB | Client & server rejection |
| Total files size | 5KB | Client filtering |
| File types | Text-based only | Extension whitelist |
| Image files | Not allowed | Automatic exclusion |

**Supported Extensions:**
`.md`, `.txt`, `.json`, `.yaml`, `.yml`, `.toml`, `.ts`, `.js`, `.jsx`, `.tsx`, `.py`, `.go`, `.rs`, `.java`, `.cpp`, `.c`, `.h`, `.cs`, `.rb`, `.php`, `.html`, `.css`, `.xml`, `.env`, `.cfg`, `.ini`, `.conf`

**Excluded Types:**
- Images: `.jpg`, `.jpeg`, `.png`, `.gif`, `.svg`, `.webp`, `.bmp`, `.ico`
- Binary: `.exe`, `.dll`, `.so`, `.bin`, `.dat`
- Archives: `.zip`, `.tar`, `.gz`, `.rar`, `.7z`
- Videos: `.mp4`, `.avi`, `.mov`, `.wmv`

**Filtering Logic:**
```typescript
const contextToSend = contextFiles
  .filter(file => {
    if (isImageLike(file)) return false
    if (file.size > 2000) return false
    if (totalSize + file.size > 5000) return false
    totalSize += file.size
    return true
  })
  .map(file => {
    if (file.content.length > 2000) {
      return {
        ...file,
        content: file.content.substring(0, 2000) + '\n[File truncated]'
      }
    }
    return file
  })
```

**Business Logic:**
- Context files ONLY used in Requirements phase
- Filtered before prompt construction
- User is NOT notified of exclusions
- Truncation is silent
- Files embedded in user prompt, not sent separately

**Why:** Token limits prevent including large files. Images are excluded due to size.

---

## Token Management

### Rule 9: Total Token Limit

**Description:** Each OpenRouter API call has a hard limit of 32,768 tokens.

**Token Budget Allocation:**

| Component | Allocation | Tokens |
|-----------|------------|--------|
| System Prompt | ~5% | ~1,638 |
| User Prompt | ~70% | ~22,938 |
| Output | 25% | 8,192 |
| Safety Buffer | ~0.3% | ~100 |
| **Total** | **100%** | **32,768** |

**Token Estimation:**
```typescript
function estimateTokens(text: string): number {
  // Based on OpenAI/Anthropic tokenization
  return Math.ceil(text.length / 3.7)
}
```

**Validation:**
```typescript
const systemTokens = estimateTokens(systemPrompt)
const userTokens = estimateTokens(userPrompt)
const outputTokens = 8192
const totalTokens = systemTokens + userTokens + outputTokens

if (totalTokens > 32768) {
  throw new Error(`Token limit exceeded: ${totalTokens} > 32,768`)
}
```

**Business Logic:**
- Validation happens client-side AND server-side
- Client validation prevents unnecessary API calls
- Server validation is authoritative
- Exceeding limit results in immediate error

### Rule 10: Token Clamping

**Description:** If token limit is exceeded, server automatically truncates content.

**Clamping Strategy:**
```typescript
function clampPrompts(system, user, limit = 32768, output = 8192) {
  const inputBudget = limit - output - 100  // 24,576 tokens

  // Preserve system prompt (20% of budget)
  const maxSystemTokens = Math.floor(inputBudget * 0.2)  // ~4,915

  // User gets remaining budget (80%)
  const userBudget = inputBudget - actualSystemTokens  // ~19,661

  // If user exceeds budget, use middle-out truncation
  if (userTokens > userBudget) {
    const maxChars = userBudget * 3.7
    const keepStart = Math.floor(maxChars * 0.6)  // 60% from start
    const keepEnd = Math.floor(maxChars * 0.3)    // 30% from end

    return {
      system: clampedSystem,
      user: user.substring(0, keepStart) +
            '\n\n[...content truncated to fit token limits...]\n\n' +
            user.substring(user.length - keepEnd),
      clamped: true
    }
  }

  return {system, user, clamped: false}
}
```

**Truncation Order:**
1. Strip binary content (base64 images, etc.)
2. Preserve system prompt (max 20% of budget)
3. Truncate user prompt using middle-out strategy
4. Keep beginning (context) and end (most recent info)

**Business Logic:**
- Only happens server-side
- User is NOT prompted or notified
- Truncation marker inserted in content
- Original content NOT saved anywhere

**Why:** Prevents API errors while preserving most important information (beginning and end).

---

## Storage and Persistence

### Rule 11: Storage Locations

**Description:** Different types of data stored in different browser storage mechanisms.

**sessionStorage** (cleared on browser close):
```typescript
// Security-sensitive
'openspec-api-key'          // OpenRouter API key
'openspec-api-key-tested'   // Key validation status

// User preferences
'openspec-selected-model'   // Selected AI model
'openspec-prompt'           // Feature description
'openspec-context-files'    // Uploaded files
```

**localStorage** (persists indefinitely):
```typescript
// Workflow state
'openspec-workflow-state'   // Complete SpecState object
{
  phase: WorkflowPhase,
  requirements: string,
  design: string,
  tasks: string,
  approvals: ApprovalState,
  timing: PhaseTiming,
  apiResponses: APIResponseInfo,
  featureName: string,
  description: string,
  context: ContextFile[],
  isGenerating: boolean,
  error: string | null
}
```

**Business Logic:**
- API key in sessionStorage for security (cleared on close)
- Workflow in localStorage for persistence (resume after close)
- Data validated and migrated on load
- Corrupted data triggers clean slate

### Rule 12: Data Migration

**Description:** Automatically migrate old data structures to new format.

**Migration Process:**
```typescript
function validateData(data): data is SpecState {
  if (!data || typeof data !== 'object') return false

  // Ensure all required fields exist
  const hasBasicFields =
    'phase' in data &&
    'approvals' in data &&
    'requirements' in data

  if (!hasBasicFields) return false

  // Add missing fields with defaults
  if (!data.timing) {
    data.timing = {
      requirements: {startTime: 0, endTime: 0, elapsed: 0},
      design: {startTime: 0, endTime: 0, elapsed: 0},
      tasks: {startTime: 0, endTime: 0, elapsed: 0}
    }
  }

  if (!data.apiResponses) {
    data.apiResponses = {
      requirements: null,
      design: null,
      tasks: null
    }
  }

  return true
}
```

**Business Logic:**
- Runs on every app load
- Adds missing fields with safe defaults
- Fixes corrupted structures
- Logs migration events for debugging
- Never deletes data (only adds/fixes)

**Why:** Allows schema evolution without breaking existing users' saved workflows.

### Rule 13: State Corruption Detection

**Description:** Detect and automatically fix inconsistent workflow state.

**Corruption Scenarios:**

| Scenario | Detection | Fix |
|----------|-----------|-----|
| Has requirements but phase = 'requirements' | `state.requirements.length > 0 && state.phase === 'requirements'` | Force phase to 'design' |
| Has design but phase = 'requirements' | `state.design.length > 0 && state.phase === 'requirements'` | Force phase to 'design', approve requirements |
| Has tasks but not on tasks phase | `state.tasks.length > 0 && state.phase !== 'tasks'` | Force phase to 'tasks', approve all previous |

**Auto-correction:**
```typescript
useEffect(() => {
  // Detect phase regression
  if (state.requirements && state.phase === 'requirements' && state.approvals.requirements) {
    console.warn('[StateCorruption] Auto-correcting phase')
    setState(prev => ({...prev, phase: 'design'}))
  }

  if (state.design && state.phase === 'requirements') {
    setState(prev => ({
      ...prev,
      phase: 'design',
      approvals: {...prev.approvals, requirements: true}
    }))
  }

  if (state.tasks && (state.phase === 'requirements' || state.phase === 'design')) {
    setState(prev => ({
      ...prev,
      phase: 'tasks',
      approvals: {requirements: true, design: true, tasks: false}
    }))
  }
}, [state.requirements, state.design, state.tasks, state.phase])
```

**Business Logic:**
- Runs on every state change
- Silent auto-correction (no user notification)
- Logs warnings for debugging
- Never regresses phase backwards
- Approvals set to match content existence

**Why:** localStorage can become corrupted due to browser issues, extension interference, or code bugs.

---

## Security Rules

### Rule 14: API Key Security

**Description:** OpenRouter API keys must be protected from exposure.

**Storage Rules:**
```typescript
// ✅ ALLOWED
sessionStorage.setItem('openspec-api-key', apiKey)  // Cleared on close

// ❌ FORBIDDEN
localStorage.setItem('openspec-api-key', apiKey)    // Persists forever
console.log('API Key:', apiKey)                      // Logs to console
analytics.track('api-key', apiKey)                   // Sends to external service
```

**Display Rules:**
```typescript
// ✅ ALLOWED - Masking
function maskApiKey(key: string): string {
  return key.substring(0, 10) + '*'.repeat(54) + key.substring(64)
}
// Display: "sk-or-v1-**************************************************z567"

// ❌ FORBIDDEN - Full display
<input value={apiKey} />
```

**Transmission Rules:**
```typescript
// ✅ ALLOWED - HTTPS only
await fetch('https://api.openrouter.ai/...', {
  headers: {'Authorization': `Bearer ${apiKey}`}
})

// ❌ FORBIDDEN - HTTP
await fetch('http://api.openrouter.ai/...', ...)

// ❌ FORBIDDEN - Query parameters
await fetch(`https://api.openrouter.ai/...?key=${apiKey}`)
```

**Business Logic:**
- API key never appears in URL
- API key never logged to console
- API key never sent to analytics
- API key never persisted long-term
- API key cleared on logout/reset

### Rule 15: Input Sanitization

**Description:** All user input must be sanitized before display.

**XSS Prevention:**
```typescript
// ✅ SAFE - React auto-escapes
<div>{userInput}</div>

// ❌ UNSAFE - Direct HTML injection
<div dangerouslySetInnerHTML={{__html: userInput}} />

// ✅ SAFE - Markdown with sanitization
<ReactMarkdown>
  {userInput}
</ReactMarkdown>
```

**SQL Injection Prevention:**
```typescript
// ✅ SAFE - Parameterized query
await db.query(
  'SELECT * FROM specs WHERE id = $1',
  [userId]
)

// ❌ UNSAFE - String concatenation
await db.query(
  `SELECT * FROM specs WHERE id = '${userId}'`
)
```

**Business Logic:**
- All React rendering is auto-escaped
- Markdown uses react-markdown (safe by default)
- No direct HTML injection allowed
- No eval() or Function() constructor

---

## Error Handling

### Rule 16: Error Classification

**Description:** All errors are classified and handled appropriately.

**Error Hierarchy:**
```typescript
class AppError extends Error {
  constructor(
    public statusCode: number,
    public message: string,
    public code: string,
    public recoverable: boolean
  ) {}
}

class ValidationError extends AppError {
  constructor(message: string) {
    super(400, message, 'VALIDATION_ERROR', true)
  }
}

class AuthenticationError extends AppError {
  constructor() {
    super(401, 'Invalid API key', 'AUTH_ERROR', true)
  }
}

class TokenLimitError extends AppError {
  constructor() {
    super(400, 'Token limit exceeded', 'TOKEN_LIMIT', true)
  }
}

class NetworkError extends AppError {
  constructor() {
    super(503, 'Network unavailable', 'NETWORK_ERROR', true)
  }
}

class UnknownError extends AppError {
  constructor(original: Error) {
    super(500, 'Unexpected error occurred', 'UNKNOWN_ERROR', false)
  }
}
```

**Error Handling:**
```typescript
try {
  await generateWithData(...)
} catch (error) {
  if (error instanceof ValidationError) {
    // Show user-friendly message, allow retry
    showError(error.message)
    setState(prev => ({...prev, isGenerating: false}))
  } else if (error instanceof AuthenticationError) {
    // Clear API key, force re-entry
    clearAPIKey()
    showError('Please enter a valid API key')
  } else if (error instanceof TokenLimitError) {
    // Suggest reducing input
    showError('Content too large. Please reduce description or context files.')
  } else if (error instanceof NetworkError) {
    // Show retry button
    showError('Network error. Please retry.')
  } else {
    // Unknown error - show generic message, log for debugging
    console.error('[UnknownError]', error)
    showError('An unexpected error occurred. Please try again.')
  }
}
```

### Rule 17: Error Recovery

**Description:** Users must be able to recover from all errors without data loss.

**Recovery Strategies:**

| Error Type | Recovery Strategy |
|------------|-------------------|
| Validation | Fix input and retry |
| Authentication | Re-enter API key |
| Token Limit | Reduce input size and retry |
| Network | Wait and retry (automatic or manual) |
| Rate Limit | Wait (show countdown) and retry |
| Unknown | Reset to last stable state |

**State Preservation:**
```typescript
try {
  setState(prev => ({...prev, isGenerating: true, error: null}))
  await generateWithData(...)
} catch (error) {
  // State reverts to last good state
  setState(prev => ({
    ...prev,
    isGenerating: false,
    error: error.message,
    // Content NOT cleared - user can retry
  }))
}
```

**Business Logic:**
- Errors never clear generated content
- Errors never reset workflow phase
- Errors never invalidate approvals
- Users can always retry after error
- State preserved for retry attempts

---

## Summary

OpenSpecification enforces strict business rules to ensure:
1. **Consistency** - Sequential workflow prevents inconsistent specs
2. **Quality** - Approval gates ensure review at each step
3. **Performance** - Token limits prevent API failures
4. **Security** - API keys protected from exposure
5. **Reliability** - Comprehensive error handling with recovery
6. **Persistence** - Data saved across sessions with migration

All rules are enforced through a combination of client-side validation, server-side enforcement, and runtime checks.
