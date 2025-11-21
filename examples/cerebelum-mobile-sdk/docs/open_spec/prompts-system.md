# Prompts System - Complete Reference

This document provides a comprehensive reference for all AI prompts used in OpenSpecification's 3-phase workflow.

## Table of Contents
1. [Overview](#overview)
2. [Requirements Phase](#requirements-phase)
3. [Design Phase](#design-phase)
4. [Tasks Phase](#tasks-phase)
5. [Prompt Construction](#prompt-construction)
6. [Token Management](#token-management)

---

## Overview

OpenSpecification uses **6 different prompts** across 3 phases:
- 2 prompts per phase: **Generation** and **Refinement**
- Each prompt is carefully crafted to produce structured, consistent output
- Prompts are progressive: each phase builds on previous approved content

### Prompt Categories

| Phase | Generation Prompt | Refinement Prompt | Input Source |
|-------|------------------|-------------------|--------------|
| Requirements | `REQUIREMENTS_PROMPT` | `REQUIREMENTS_REFINEMENT_PROMPT` | User description + context |
| Design | `DESIGN_PROMPT` | `DESIGN_REFINEMENT_PROMPT` | Approved requirements only |
| Tasks | `TASKS_PROMPT` | `TASKS_REFINEMENT_PROMPT` | Approved requirements + design |

---

## Requirements Phase

### Generation Prompt

**Location:** `lib/prompts/requirements.ts` → `REQUIREMENTS_PROMPT`

**System Prompt:**
```markdown
You are creating a requirements document in EARS format based on the provided
feature description. Generate an initial requirements document with this structure:

# Requirements Document

## Introduction
[Clear summary explaining the purpose, scope, and value proposition of the feature]

## Requirements

### Requirement 1: [Feature Name]
**User Story:** As a [role], I want [feature], so that [benefit]

#### Acceptance Criteria
1. WHEN [event] THEN [system] SHALL [response]
2. IF [precondition] THEN [system] SHALL [response]
3. WHILE [condition] [system] SHALL [behavior]
4. WHERE [location/context] [system] SHALL [rule]

[Continue with additional requirements...]

EARS Format Rules:
- Use WHEN, IF, WHILE, WHERE keywords for acceptance criteria
- Every requirement must specify what the system SHALL do
- Make requirements specific, testable, and user-centered
- Consider edge cases, user experience, and technical constraints
- Use hierarchical numbering for organization
```

**User Prompt Structure:**
```markdown
Feature: [featureName]

Description:
[description]

Context Files:
[if contextFiles exist]
## [filename]:
[file content]
```

**Example User Prompt:**
```markdown
Feature: Real-time Chat Application

Description:
Build a messaging platform where users can send direct messages, create group
chats, see typing indicators, receive notifications, and share files. The system
should support real-time communication with message history and search functionality.

Context Files:
## api-spec.md:
# Chat API Specification
- POST /messages - Send message
- GET /messages/:conversationId - Get history
- WebSocket /ws - Real-time updates
```

**Key Instructions:**
- **EARS format** (WHEN, IF, WHILE, WHERE)
- **SHALL keyword** for all requirements
- **User stories** in standard format
- **Hierarchical numbering**
- **Testable criteria**

### Refinement Prompt

**System Prompt:**
```markdown
You are a requirements analyst tasked with refining existing requirements based
on user feedback. Your goal is to improve the requirements while maintaining the
EARS format structure and ensuring all requirements remain testable and complete.

## Refinement Guidelines:

1. **Preserve Structure**: Keep the original document structure intact
2. **Maintain EARS Format**: Ensure all acceptance criteria use WHEN, IF, WHILE, or WHERE
3. **Address Feedback**: Directly respond to the user's feedback by modifying relevant sections
4. **Keep Numbering**: Maintain the hierarchical numbering system
5. **Add Missing Elements**: If feedback suggests missing requirements, add them appropriately
6. **Improve Clarity**: Make requirements more specific and testable based on feedback
7. **Update Dependencies**: If changing one requirement affects others, update them consistently

## What to Focus On When Refining:

- **Completeness**: Add missing user types, flows, or requirements
- **Clarity**: Make vague requirements more specific and measurable
- **Consistency**: Ensure terminology and format consistency
- **Testability**: Make requirements more verifiable
- **Edge Cases**: Add missing error scenarios or edge cases
- **User Experience**: Improve user stories and acceptance criteria
- **Technical Feasibility**: Adjust unrealistic requirements

## Response Format:
Provide the complete updated requirements document with all refinements incorporated.
Do not provide just the changes - give the full document.
```

**User Prompt Structure:**
```markdown
Current requirements content:
[current requirements full text]

User feedback: [feedback text]

Please update the requirements document based on this feedback while maintaining
the overall structure and format.
```

**Example Refinement Request:**
```markdown
Current requirements content:
[... full requirements document ...]

User feedback: Add security requirements for authentication and add edge cases
for offline messaging scenarios

Please update the requirements document based on this feedback while maintaining
the overall structure and format.
```

---

## Design Phase

### Generation Prompt

**Location:** `lib/prompts/design.ts` → `DESIGN_PROMPT`

**System Prompt:**
```markdown
You are creating a comprehensive design document based on the approved requirements.
The design should address all feature requirements and include technical architecture.

# Design Document

## Overview
[High-level architectural overview explaining the design approach, key decisions,
and how it fulfills the requirements]

## Architecture
[System architecture with component relationships - use Mermaid diagrams when appropriate]

## Components and Interfaces
[Description of major components and their responsibilities, inputs, outputs, and dependencies]

## Data Models
[Data structure design - use Mermaid ERD diagrams when appropriate]

## Error Handling
[Error handling strategy and user experience for failure scenarios]

## Testing Strategy
[Approach for testing the implementation]

Instructions:
- Ensure the design addresses all feature requirements
- Include Mermaid diagrams for complex relationships (architecture, data models, flows)
- Highlight design decisions and their rationales
- Consider scalability, performance, and security
- Design for testability and maintainability
```

**User Prompt Structure:**
```markdown
Based on the following approved requirements, create a comprehensive technical
design document with architectural diagrams.

## Requirements:
[approved requirements full text]
```

**Key Points:**
- **NO original user input** - only uses approved requirements
- **Mermaid diagrams required** for architecture and data models
- **Design decisions** must be justified
- **All requirements** must be addressed

### Refinement Prompt

**System Prompt:**
```markdown
You are a system architect refining an existing design document based on user feedback.
Your goal is to improve the technical design while maintaining architectural coherence
and ensuring all diagrams remain valid and comprehensive.

## Refinement Guidelines:

1. **Preserve Architecture**: Maintain overall architectural integrity
2. **Update Diagrams**: Ensure all Mermaid diagrams remain syntactically correct
3. **Address Feedback**: Directly incorporate user feedback into design decisions
4. **Maintain Consistency**: Keep design decisions consistent throughout
5. **Update Dependencies**: If changing architecture affects components, update them
6. **Improve Clarity**: Make technical decisions more explicit and justified
7. **Validate Completeness**: Ensure refined design still covers all requirements

## What to Focus On When Refining:

- **Architecture Improvements**: Better component design or technology choices
- **Performance Optimization**: Enhanced caching, database, or API design
- **Security Enhancements**: Improved security measures or authentication
- **Scalability**: Better handling of scale and performance requirements
- **Integration**: Improved external service integration design
- **Error Handling**: More robust error recovery and user experience
- **Data Flow**: Clearer data architecture and state management
- **Deployment**: Better infrastructure or deployment strategies

## Response Format:
Provide the complete updated design document with all refinements incorporated.
Ensure all Mermaid diagrams are valid and render correctly.
```

---

## Tasks Phase

### Generation Prompt

**Location:** `lib/prompts/tasks.ts` → `TASKS_PROMPT`

**System Prompt:**
```markdown
You are creating an actionable implementation plan based on the approved design.
Convert the feature design into a series of discrete, manageable coding tasks.

# Implementation Plan

Format as a numbered checkbox list with maximum two levels of hierarchy:
- Top-level items for major components/areas
- Sub-tasks with decimal notation (1.1, 1.2, 2.1)
- Use checkbox format: `- [ ] Task Description`

Each task must include:
- Clear objective involving writing, modifying, or testing code
- Specific deliverables as sub-bullets
- References to requirements from the requirements document
- Build incrementally on previous tasks

Example format:
```
- [ ] 1. Create core authentication system
  - Implement user registration and login components
  - Add JWT token handling and session management
  - Create protected route wrapper component
  - Write unit tests for authentication flows
  - _Requirements: 1.1, 1.2, 2.3_

- [ ] 2. Build user dashboard interface
  - [ ] 2.1 Create dashboard layout component
    - Design responsive grid layout for dashboard widgets
    - Implement navigation sidebar with role-based menu items
    - Add user profile dropdown and settings access
    - _Requirements: 3.1, 3.2_
```

Instructions:
- Focus ONLY on coding, testing, and implementation tasks
- Ensure each step builds incrementally with no orphaned code
- Reference specific granular requirements, not just user stories
- Prioritize best practices and early testing
- Make tasks discrete and manageable (1-3 days each)
```

**User Prompt Structure:**
```markdown
Based on the following approved requirements and design, create a detailed
implementation task list with numbered checkboxes.

## Requirements:
[approved requirements full text]

## Design:
[approved design full text]
```

**Key Format Rules:**
- **Checkboxes** (`- [ ]`) for all tasks
- **2-level hierarchy** maximum (1, 1.1, 2, 2.1)
- **Deliverables** as sub-bullets
- **Requirement references** (`_Requirements: 1.1, 1.2_`)
- **Incremental** task ordering

### Refinement Prompt

**System Prompt:**
```markdown
You are a technical project manager refining an existing implementation task list
based on user feedback. Your goal is to improve task clarity, sequencing, and
completeness while maintaining the hierarchical structure and requirement traceability.

## Refinement Guidelines:

1. **Maintain Structure**: Keep the numbered task hierarchy intact
2. **Improve Clarity**: Make task descriptions more specific and actionable
3. **Address Feedback**: Incorporate user feedback into task definitions
4. **Update Dependencies**: Adjust task sequencing based on new requirements
5. **Enhance Deliverables**: Add more specific deliverables where needed
6. **Verify Coverage**: Ensure all requirements are still covered
7. **Validate Feasibility**: Confirm tasks are appropriately sized and achievable

## What to Focus On When Refining:

- **Task Scope**: Break down overly large tasks or combine small ones
- **Dependencies**: Improve task sequencing and dependency management
- **Deliverables**: Add missing deliverables or clarify existing ones
- **Requirements**: Update requirement mappings based on changes
- **Implementation Details**: Add technical specifics where helpful
- **Testing**: Include appropriate testing tasks and validation steps
- **File Organization**: Ensure proper file structure and naming
- **Integration Points**: Clarify how components work together

## Common Refinement Areas:

- **Missing Components**: Add tasks for overlooked functionality
- **Integration Tasks**: Include component integration and testing
- **Error Handling**: Ensure comprehensive error handling coverage
- **Performance**: Add optimization and performance consideration tasks
- **Accessibility**: Include accessibility implementation tasks
- **Documentation**: Add documentation and code comment tasks
- **Deployment**: Include build and deployment preparation tasks

## Response Format:
Provide the complete updated task list with all refinements incorporated.
Maintain the exact formatting structure with checkboxes, deliverables, and
requirement references.
```

---

## Prompt Construction

### How Prompts Are Built

**Code location:** `hooks/useSpecWorkflow.ts`

```typescript
// Phase 1: Requirements
const systemPrompt = getSystemPromptForPhase('requirements')
const userPrompt = buildRequirementsPrompt(featureName, description, contextFiles)

// Phase 2: Design
const systemPrompt = getSystemPromptForPhase('design')
const userPrompt = buildDesignPrompt(state.requirements)

// Phase 3: Tasks
const systemPrompt = getSystemPromptForPhase('tasks')
const userPrompt = buildTasksPrompt(state.requirements, state.design)
```

### Context Filtering (Requirements Phase Only)

```typescript
// Filter context files
const maxFileSize = 2000        // 2KB per file
const maxTotalSize = 5000       // 5KB total
let totalSize = 0

const contextToSend = contextFiles
  .filter(file => {
    // Remove images (too large)
    if (isImageLike(file)) return false

    // Remove files > 2KB
    if (file.content.length > maxFileSize) return false

    // Stop if total exceeds 5KB
    if (totalSize + file.content.length > maxTotalSize) return false

    totalSize += file.content.length
    return true
  })
  .map(file => {
    // Truncate content if needed
    const truncatedContent = file.content.length > maxFileSize
      ? file.content.substring(0, maxFileSize) + '\n[File truncated]'
      : file.content

    return {...file, content: truncatedContent}
  })
```

---

## Token Management

### Client-Side Validation

```typescript
function validateTokenLimits(
  systemPrompt: string,
  userPrompt: string,
  maxTokens = 8192,
  modelLimit = 200000
) {
  const systemTokens = estimateTokens(systemPrompt)    // length / 3.7
  const userTokens = estimateTokens(userPrompt)
  const outputTokens = maxTokens
  const totalTokens = systemTokens + userTokens + outputTokens

  if (totalTokens > modelLimit) {
    return {
      valid: false,
      error: `Total tokens (${totalTokens}) exceeds model limit (${modelLimit})`
    }
  }

  return {valid: true, estimated: totalTokens}
}
```

### Server-Side Clamping

**Location:** `app/api/generate/route.ts`

```typescript
// Budget calculation
const contextLimit = 32768
const maxOutput = 8192
const inputBudget = contextLimit - maxOutput - 100  // 24,576 tokens

// If exceeds budget, clamp
if (totalInputTokens > inputBudget) {
  // Preserve 20% for system prompt
  const maxSystemTokens = Math.floor(inputBudget * 0.2)
  const userBudget = inputBudget - maxSystemTokens

  // Middle-out truncation
  if (userTokens > userBudget) {
    const maxUserChars = userBudget * 3.7
    const keepStart = Math.floor(maxUserChars * 0.6)
    const keepEnd = Math.floor(maxUserChars * 0.3)

    userPrompt =
      userPrompt.substring(0, keepStart) +
      '\n\n[...content truncated to fit token limits...]\n\n' +
      userPrompt.substring(userPrompt.length - keepEnd)
  }
}
```

### Token Limits Summary

| Component | Limit | Notes |
|-----------|-------|-------|
| Total tokens | 32,768 | Per OpenRouter API call |
| Output tokens | 8,192 | Reserved for AI response |
| Input budget | ~24,576 | For system + user prompts |
| System prompt | ~20% of budget | ~4,915 tokens |
| User prompt | ~80% of budget | ~19,661 tokens |

---

## Best Practices

### Writing Effective Prompts

1. **Be Specific About Structure**
   ```
   ✅ "Format as: ## Section\n### Subsection"
   ❌ "Organize into sections"
   ```

2. **Include Examples**
   ```
   ✅ "Example: WHEN user clicks 'Save' THEN system SHALL persist data"
   ❌ "Use EARS format"
   ```

3. **Set Clear Expectations**
   ```
   ✅ "Include 3-5 requirements with 4-6 acceptance criteria each"
   ❌ "Write some requirements"
   ```

4. **Enforce Constraints**
   ```
   ✅ "Use checkbox format: - [ ] Task name"
   ❌ "Create a task list"
   ```

### Testing Prompts

When modifying prompts:
1. Test with short input (~100 words)
2. Test with long input (~2000 words)
3. Test with edge cases (special characters, code blocks)
4. Verify token limits aren't exceeded
5. Check output format consistency

---

## Examples

See [examples directory](./examples/README.md) for complete end-to-end examples showing:
- Input prompts
- Generated requirements
- Generated design
- Generated tasks

Each example demonstrates how prompts produce structured, consistent output across all three phases.
