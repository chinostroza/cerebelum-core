# Examples - Complete Workflow Demonstrations

This directory contains complete end-to-end examples of OpenSpecification's 3-phase workflow, showing real inputs and outputs.

## Available Examples

### 1. [Chat Application](./01-chat-application/)
A real-time messaging platform with direct messages, group chats, and file sharing.

**Complexity:** Medium
**Features:** WebSocket communication, user authentication, file uploads, notifications
**Best for:** Understanding real-time features and complex state management

### 2. [E-commerce Shopping Cart](./02-ecommerce-cart/)
A shopping cart system with product browsing, cart management, and checkout.

**Complexity:** Medium
**Features:** Product catalog, inventory management, payment integration, order processing
**Best for:** Understanding CRUD operations and transaction flows

### 3. [Analytics Dashboard](./03-analytics-dashboard/)
A data visualization dashboard with charts, filters, and real-time updates.

**Complexity:** High
**Features:** Data aggregation, visualization, filtering, export functionality
**Best for:** Understanding data-heavy applications and visualization requirements

## Example Structure

Each example contains 4 files:

```
01-example-name/
├── input.md           # User's original input
├── requirements.md    # Phase 1 output (EARS format)
├── design.md          # Phase 2 output (Architecture + diagrams)
└── tasks.md           # Phase 3 output (Implementation plan)
```

## How to Use These Examples

### For Learning
1. Read `input.md` to see what the user provided
2. Read `requirements.md` to see how informal input becomes formal requirements
3. Read `design.md` to see how requirements become architecture
4. Read `tasks.md` to see how design becomes actionable tasks

### For Testing
Use these examples to:
- Test prompt modifications
- Verify output consistency
- Benchmark performance (timing, token usage)
- Validate format compliance (EARS, Mermaid, checkboxes)

### For Templates
Use these as templates when creating your own specifications:
- Copy the structure
- Adapt the content to your needs
- Follow the same formatting conventions

## Metrics Comparison

| Example | Requirements | Design | Tasks | Total Tokens | Total Cost |
|---------|-------------|--------|-------|--------------|------------|
| Chat Application | 2,490 tokens | 6,000 tokens | 5,500 tokens | 13,990 | $0.00042 |
| E-commerce Cart | 2,800 tokens | 5,200 tokens | 6,100 tokens | 14,100 | $0.00045 |
| Analytics Dashboard | 3,200 tokens | 7,500 tokens | 7,800 tokens | 18,500 | $0.00055 |

*Note: Metrics are approximate and vary based on model and input complexity*

## Key Observations

### Requirements Phase
- Always uses EARS format (WHEN, IF, WHILE, WHERE)
- Includes user stories for each requirement
- Hierarchical numbering (1, 1.1, 1.2, etc.)
- Covers functional and non-functional requirements
- Typical length: 1,500-3,000 words

### Design Phase
- Always includes architecture overview
- Uses Mermaid diagrams for visualization
- Describes components and interfaces
- Addresses error handling and testing
- Typical length: 2,000-4,000 words

### Tasks Phase
- Always uses checkbox format
- 2-level hierarchy maximum
- References requirements for traceability
- Includes specific deliverables
- Testing tasks included
- Typical count: 50-100 tasks

## Common Patterns

### Requirement Patterns
```markdown
### Requirement N: [Feature Name]
**User Story:** As a [role], I want [feature], so that [benefit]

#### Acceptance Criteria
1. WHEN [trigger] THEN system SHALL [action]
2. IF [condition] THEN system SHALL [response]
3. WHILE [state] system SHALL [behavior]
4. WHERE [context] system SHALL [rule]
```

### Design Patterns
```markdown
## Architecture
[Mermaid diagram showing system components]

## Components and Interfaces
- **Component Name**: [Description]
  - Input: [What it receives]
  - Output: [What it produces]
  - Dependencies: [What it depends on]
```

### Task Patterns
```markdown
- [ ] N. [Major Component/Area]
  - [Deliverable 1]
  - [Deliverable 2]
  - _Requirements: X.Y, Z.A_

  - [ ] N.1 [Sub-task]
    - [Specific deliverable]
    - [Test to write]
    - _Requirements: X.Y_
```

## Using Examples in Your Development

### As Reference
When building a feature, use examples to:
1. Structure your requirements using EARS format
2. Design architecture following proven patterns
3. Break down work into manageable tasks

### As Validation
After generating your specification:
1. Compare structure to examples
2. Verify all sections are present
3. Check formatting consistency
4. Ensure requirement traceability

### As Training Data
If building similar systems:
1. Study how prompts produce outputs
2. Understand what makes good requirements
3. Learn architectural patterns
4. See task breakdown strategies

## Contributing Examples

To add a new example:

1. Create directory: `XX-example-name/`
2. Add all 4 files (input, requirements, design, tasks)
3. Use real, complete content (not placeholders)
4. Follow existing formatting conventions
5. Update this README with metrics

Example should demonstrate:
- Clear user intent in input
- Well-structured requirements
- Comprehensive design
- Actionable tasks
- Complete traceability

## Questions & Feedback

If examples are unclear or you need additional examples:
- Open an issue describing what you need
- Specify complexity level and domain
- Mention specific features to demonstrate
