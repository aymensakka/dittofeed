

📄 /bootstrap_context

You are an expert AI coding agent operating inside this Git repository.

────────────────────────────────────────
0. MEMORY
────────────────────────────────────────
/create_memory context_engineering
- Purpose : Persist global rules, file map, architectural decisions, and
  DOC⇄code reconciliation notes.
- Initial : Copy §§1–4 below into memory.

────────────────────────────────────────
1. GLOBAL RULES  (persistent)
────────────────────────────────────────
• Obey every instruction in **projectpath/claude.md** exactly.  
• Never invent file- or folder-names outside §2.  
• Legacy documentation (PRDs, design docs, ADRs) resides in
  **`projectpath/docs/`** – treat it as read-only.  
• Test-Driven Development: write unit tests first, code second.  
• A task is done only when `pytest -q` returns 0 failures.  
• Maintain **projectpath/AI_REPORT.md** as a running checklist.  
• **If a Markdown file exists but is empty, treat it as missing and populate it
  with the template in §5.**

────────────────────────────────────────
2. REQUIRED FILE & FOLDER MAP
────────────────────────────────────────
Skip any item that already exists **and has content**;  
if it is missing **or empty**, create/populate exactly as specified.

| Path | Populate With |
|------|---------------|
| **projectpath/.claude/settings.local.json** | Claude-Code settings (derive from `pyproject.toml`, `requirements.txt`, configs, and `README.md`). |
| **projectpath/claude.md** | Global rules & conventions. Generate best-practice guidelines aligning with repo style if file missing/empty. |
| **projectpath/initial_example.md** | Template text in §5a (PRD-aware). |
| **projectpath/initial.md** | Copy `initial_example.md`, then **augment** it using insights from legacy docs, code-base analysis, and DB schema. Flag any gaps/inconsistencies. |
| **projectpath/examples/** | Ensure folder exists; create `.keep` if empty. |
| **projectpath/.claude/commands/generate_PRP.md** | Template text in §5b (“Create PRP”). |
| **projectpath/.claude/commands/execute_PRP.md** | Template text in §5c (“Execute BASE PRP”). |
| **projectpath/PRPs/templates/prp_base.md** | Template text in §5d (“prp_base.md”). |
| **projectpath/PRPs/** | Folder where the agent writes *new* PRPs. |
| **projectpath/PRDs/** | Folder where the agent writes *new* PRDs. |
| **projectpath/AI_REPORT.md** | Running checklist (✅ / 🔄 / 🆕). Create if absent. |

*(⤷ Note: `projectpath/docs/` already exists and is read-only for analysis.)*

────────────────────────────────────────
3. DOC ⇄ CODE ⇄ SCHEMA CONSISTENCY CHECK
────────────────────────────────────────
Before generating or executing any PRP:

1. **Parse Legacy Docs**  
   • Read every Markdown / text file under `projectpath/docs/`.  
   • Extract declared features, success criteria, open questions, TODOs.

2. **Scan Code-Base & DB Schema**  
   • Produce file list (`git ls-files` or `tree`).  
   • Locate schema definitions (SQL, migrations, ORM models).  
   • Detect mismatches: feature described but not implemented, undocumented
     model fields, missing tests, etc.

3. **Gap Report**  
   • Append a **“Gaps & Inconsistencies”** section to
     `projectpath/AI_REPORT.md`, listing issues with unique IDs (GAP-001 …).

4. **Seed `initial.md`**  
   • Pull concrete details from legacy docs that are still relevant.  
   • For each gap, add a “❗ Needs clarification” bullet.  
   • Reference code paths or schema objects that illustrate the mismatch.

────────────────────────────────────────
4. WORKFLOW  (strict order)
────────────────────────────────────────
1. **File Audit, Creation & Consistency Pass**  
   • Execute §2 (file creation) and §3 (doc-code-schema check).  
   • Update *AI_REPORT.md*.

2. **Generate PRP**  

/generate_PRP projectpath/initial.md

Save as `projectpath/PRPs/YYYY-MM-DD_<slug>.md`.

3. **Execute PRP**  

/execute_PRP projectpath/PRPs/YYYY-MM-DD_.md

Create / modify **only** the files listed inside that PRP.  
• When PRP instructs to publish a Product-Requirements Document, save it as  
  `projectpath/PRDs/YYYY-MM-DD_<slug>.md`.

4. **Finish** when all validation gates pass and every GAP-ID in
*AI_REPORT.md* is resolved or explicitly deferred.

────────────────────────────────────────
5. TEMPLATES  (verbatim copies)
────────────────────────────────────────
5a. **projectpath/initial_example.md**  (PRD-aware starter)
───────────────────────────────────────
```markdown
# <PROJECT / FEATURE TITLE>

> _Auto-generated from legacy docs in **/docs** + repo scan.  
> Fill in the “❗ Needs clarification” bullets before implementation._

## FEATURE OVERVIEW
- **Legacy Docs referenced**: [docs/accounting_v2.md], [docs/…]
- **High-Level Goal**: <one-sentence problem statement>
- **Key Capabilities**: <bullet list>
- **Tech Stack Snapshot**: <Next.js 14 / FastAPI 0.111 / …>

## GAPS & INCONSISTENCIES (auto-detected)
- ❗ GAP-001: PRD specifies `gift_card.balance` but DB schema column missing.
- ❗ GAP-002: No tests cover voucher expiry edge-case mentioned in docs line 42.
- ❗ GAP-003: …

## SUCCESS CRITERIA
- [ ] All gaps resolved or deferred with rationale
- [ ] New unit & integration tests pass
- [ ] CI pipeline green

*(continue with structure from earlier template: pages, components, stack, etc.)*

5b. projectpath/.claude/commands/generate_PRP.md — “Create PRP”
# Create PRP

## Feature file: $ARGUMENTS

Generate a complete PRP for general feature implementation with thorough
research. Ensure context is passed to the AI agent to enable self-validation and
iterative refinement. Read the feature file first to understand what needs to be
created, how the examples provided help, and any other considerations.

The AI agent only gets the context you are appending to the PRP and training
data. Assuma the AI agent has access to the codebase and the same knowledge
cutoff as you, so its important that your research findings are included or
referenced in the PRP. The Agent has Websearch capabilities, so pass urls to
documentation and examples.

## Research Process

1. **Codebase Analysis**
   - Search for similar features/patterns in the codebase
   - Identify files to reference in PRP
   - Note existing conventions to follow
   - Check test patterns for validation approach

2. **External Research**
   - Search for similar features/patterns online
   - Library documentation (include specific URLs)
   - Implementation examples (GitHub/StackOverflow/blogs)
   - Best practices and common pitfalls

3. **User Clarification** (if needed)
   - Specific patterns to mirror and where to find them?
   - Integration requirements and where to find them?

## PRP Generation

Using PRPs/templates/prp_base.md as template:

### Critical Context to Include and pass to the AI agent as part of the PRP

- **Documentation**: URLs with specific sections
- **Code Examples**: Real snippets from codebase
- **Gotchas**: Library quirks, version issues
- **Patterns**: Existing approaches to follow

### Implementation Blueprint

- Start with pseudocode showing approach
- Reference real files for patterns
- Include error handling strategy
- list tasks to be completed to fullfill the PRP in the order they should be
  completed

### Validation Gates (Must be Executable) eg for python

```bash
# Syntax/Style
ruff check --fix && mypy .

# Unit Tests
uv run pytest tests/ -v
```

*** CRITICAL AFTER YOU ARE DONE RESEARCHING AND EXPLORING THE CODEBASE BEFORE
YOU START WRITING THE PRP ***

*** ULTRATHINK ABOUT THE PRP AND PLAN YOUR APPROACH THEN START WRITING THE PRP
***

## Output

Save as: `PRPs/{feature-name}.md`

## Quality Checklist

- [ ] All necessary context included
- [ ] Validation gates are executable by AI
- [ ] References existing patterns
- [ ] Clear implementation path
- [ ] Error handling documented

Score the PRP on a scale of 1-10 (confidence level to succeed in one-pass
implementation using claude codes)

Remember: The goal is one-pass implementation success through comprehensive
context.
───────────────────────────────────────

5c. projectpath/.claude/commands/execute_PRP.md — “Execute BASE PRP”
# Execute BASE PRP

Implement a feature using using the PRP file.

## PRP File: $ARGUMENTS

## Execution Process

1. **Load PRP**
   - Read the specified PRP file
   - Understand all context and requirements
   - Follow all instructions in the PRP and extend the research if needed
   - Ensure you have all needed context to implement the PRP fully
   - Do more web searches and codebase exploration as needed

2. **ULTRATHINK**
   - Think hard before you execute the plan. Create a comprehensive plan
     addressing all requirements.
   - Break down complex tasks into smaller, manageable steps using your todos
     tools.
   - Use the TodoWrite tool to create and track your implementation plan.
   - Identify implementation patterns from existing code to follow.

3. **Execute the plan**
   - Execute the PRP
   - Implement all the code

4. **Validate**
   - Run each validation command
   - Fix any failures
   - Re-run until all pass

5. **Complete**
   - Ensure all checklist items done
   - Run final validation suite
   - Report completion status
   - Read the PRP again to ensure you have implemented everything

6. **Reference the PRP**
   - You can always reference the PRP again if needed

Note: If validation fails, use error patterns in PRP to fix and retry.

───────────────────────────────────────


5d. projectpath/PRPs/templates/prp_base.md


## prp_base.md
name: "Base PRP Template v2 - Context-Rich with Validation Loops" description: |

## Purpose

Template optimized for AI agents to implement features with sufficient context
and self-validation capabilities to achieve working code through iterative
refinement.

## Core Principles

1. **Context is King**: Include ALL necessary documentation, examples, and
   caveats
2. **Validation Loops**: Provide executable tests/lints the AI can run and fix
3. **Information Dense**: Use keywords and patterns from the codebase
4. **Progressive Success**: Start simple, validate, then enhance
5. **Global rules**: Be sure to follow all rules in CLAUDE.md

---

## Goal

[What needs to be built - be specific about the end state and desires]

## Why

- [Business value and user impact]
- [Integration with existing features]
- [Problems this solves and for whom]

## What

[User-visible behavior and technical requirements]

### Success Criteria

- [ ] [Specific measurable outcomes]

## All Needed Context

### Documentation & References (list all context needed to implement the feature)

```yaml
# MUST READ - Include these in your context window
- url: https://docs.dittofeed.com/introduction
  why: [Specific sections/methods you'll need]

- file: [path/to/example.py]
  why: [Pattern to follow, gotchas to avoid]

- doc: [Library documentation URL]
  section: [Specific section about common pitfalls]
  critical: [Key insight that prevents common errors]

- docfile: [PRPs/ai_docs/file.md]
  why: [docs that the user has pasted in to the project]
```

### Current Codebase tree (run `tree` in the root of the project) to get an overview of the codebase

```bash
```

### Desired Codebase tree with files to be added and responsibility of file

```bash
```

### Known Gotchas of our codebase & Library Quirks

```python
# CRITICAL: [Library name] requires [specific setup]
# Example: FastAPI requires async functions for endpoints
# Example: This ORM doesn't support batch inserts over 1000 records
# Example: We use pydantic v2 and
```

## Implementation Blueprint

### Data models and structure

Create the core data models, we ensure type safety and consistency.

```python
Examples: 
 - orm models
 - pydantic models
 - pydantic schemas
 - pydantic validators
```

### list of tasks to be completed to fullfill the PRP in the order they should be completed

```yaml
Task 1:
MODIFY src/existing_module.py:
  - FIND pattern: "class OldImplementation"
  - INJECT after line containing "def __init__"
  - PRESERVE existing method signatures

CREATE src/new_feature.py:
  - MIRROR pattern from: src/similar_feature.py
  - MODIFY class name and core logic
  - KEEP error handling pattern identical

...(...)

Task N:
...
```

### Per task pseudocode as needed added to each task

```python
# Task 1
# Pseudocode with CRITICAL details dont write entire code
async def new_feature(param: str) -> Result:
    # PATTERN: Always validate input first (see src/validators.py)
    validated = validate_input(param)  # raises ValidationError
    
    # GOTCHA: This library requires connection pooling
    async with get_connection() as conn:  # see src/db/pool.py
        # PATTERN: Use existing retry decorator
        @retry(attempts=3, backoff=exponential)
        async def _inner():
            # CRITICAL: API returns 429 if >10 req/sec
            await rate_limiter.acquire()
            return await external_api.call(validated)
        
        result = await _inner()
    
    # PATTERN: Standardized response format
    return format_response(result)  # see src/utils/responses.py
```

### Integration Points

```yaml
DATABASE:
  - migration: "Add column 'feature_enabled' to users table"
  - index: "CREATE INDEX idx_feature_lookup ON users(feature_id)"

CONFIG:
  - add to: config/settings.py
  - pattern: "FEATURE_TIMEOUT = int(os.getenv('FEATURE_TIMEOUT', '30'))"

ROUTES:
  - add to: src/api/routes.py
  - pattern: "router.include_router(feature_router, prefix='/feature')"
```

## Validation Loop

### Level 1: Syntax & Style

```bash
# Run these FIRST - fix any errors before proceeding
ruff check src/new_feature.py --fix  # Auto-fix what's possible
mypy src/new_feature.py              # Type checking

# Expected: No errors. If errors, READ the error and fix.
```

### Level 2: Unit Tests each new feature/file/function use existing test patterns

```python
# CREATE test_new_feature.py with these test cases:
def test_happy_path():
    """Basic functionality works"""
    result = new_feature("valid_input")
    assert result.status == "success"

def test_validation_error():
    """Invalid input raises ValidationError"""
    with pytest.raises(ValidationError):
        new_feature("")

def test_external_api_timeout():
    """Handles timeouts gracefully"""
    with mock.patch('external_api.call', side_effect=TimeoutError):
        result = new_feature("valid")
        assert result.status == "error"
        assert "timeout" in result.message
```

```bash
# Run and iterate until passing:
uv run pytest test_new_feature.py -v
# If failing: Read error, understand root cause, fix code, re-run (never mock to pass)
```

### Level 3: Integration Test

```bash
# Start the service
uv run python -m src.main --dev

# Test the endpoint
curl -X POST http://localhost:8000/feature \
  -H "Content-Type: application/json" \
  -d '{"param": "test_value"}'

# Expected: {"status": "success", "data": {...}}
# If error: Check logs at logs/app.log for stack trace
```

## Final validation Checklist

- [ ] All tests pass: `uv run pytest tests/ -v`
- [ ] No linting errors: `uv run ruff check src/`
- [ ] No type errors: `uv run mypy src/`
- [ ] Manual test successful: [specific curl/command]
- [ ] Error cases handled gracefully
- [ ] Logs are informative but not verbose
- [ ] Documentation updated if needed

---

## Anti-Patterns to Avoid

- ❌ Don't create new patterns when existing ones work
- ❌ Don't skip validation because "it should work"
- ❌ Don't ignore failing tests - fix them
- ❌ Don't use sync functions in async context
- ❌ Don't hardcode values that should be config
- ❌ Don't catch all exceptions - be specific

───────────────────────────────────────


────────────────────────────────────────
6. RESPONSE PROTOCOL
────────────────────────────────────────
Immediately return a task list for Step 1 (File Audit, Creation & Consistency
Pass), then begin executing it.

This version keeps **legacy documentation** safely in `projectpath/docs/` for
analysis only, while all fresh PRDs land in `projectpath/PRDs/`, ensuring a
clean separation between historical and newly engineered context.