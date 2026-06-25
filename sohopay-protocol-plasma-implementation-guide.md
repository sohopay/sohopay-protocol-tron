Claude Development Playbook
A Production-Grade Workflow for Understanding, Planning, Implementing, and Reviewing Features
Overview
This playbook is designed for working on an existing production codebase. The goal is not to immediately write code. Instead, the workflow is:

1. Understand the repository.
2. Understand the architecture.
3. Understand the ticket.
4. Design the solution.
5. Implement carefully.
6. Review your own work.
7. Verify everything before creating a PR.
Golden Rule
Never write code until you completely understand the repository and have an implementation plan.
Phase 1 — Repository Analysis
Prompt

```text
You are a Senior Staff Software Engineer joining this project.

Your first responsibility is NOT to write code.

I want you to completely understand this repository before making any modifications.

Please perform a comprehensive analysis of the entire repository.

Tasks:

1. Read the repository structure.
2. Identify every major module.
3. Explain the overall architecture.
4. Explain the application's purpose.
5. Identify the entry points.
6. Explain how the application starts.
7. Explain the build system.
8. Explain package management.
9. Explain dependency injection (if applicable).
10. Explain configuration management.
11. Explain authentication.
12. Explain authorization.
13. Explain routing.
14. Explain middleware.
15. Explain service layers.
16. Explain business logic layers.
17. Explain models/entities.
18. Explain repositories/data access.
19. Explain database architecture.
20. Explain external APIs.
21. Explain background jobs.
22. Explain queues.
23. Explain caching.
24. Explain logging.
25. Explain monitoring.
26. Explain error handling.
27. Explain testing strategy.
28. Explain deployment architecture.
29. Explain coding conventions.
30. Explain important design patterns.

Deliverables:

• Complete architecture overview
• Folder-by-folder explanation
• High-level system diagram (text format)
• Areas requiring further investigation

Do NOT modify any code.
Do NOT implement anything.
Only understand the project.

```

Phase 2 — Developer Onboarding Guide
Prompt

```text
Now create a complete developer onboarding guide.

Imagine a new senior engineer joins the team tomorrow.

Explain:

- Project purpose
- Tech stack
- Folder structure
- Entry points
- Request lifecycle
- Authentication flow
- Authorization flow
- API architecture
- Database architecture
- Service architecture
- Important models
- Important business logic
- External integrations
- Environment variables
- Build commands
- Run commands
- Test commands
- Deployment process
- CI/CD pipeline

Also explain:

- Common pitfalls
- Important coding conventions
- Files that should rarely be modified
- Common debugging workflow
- Best practices followed in this repository

Format it as a professional onboarding document.

```

Phase 3 — Repository Map
Prompt

```text
Create a repository map.

Explain every important directory.

For each folder explain:

- Purpose
- Responsibility
- Main files
- Dependencies
- Risk of modifying

Also identify:

- Shared utilities
- Configuration
- Infrastructure
- Middleware
- Controllers
- Services
- Models
- Repositories
- Helpers
- Tests

Return everything as a structured table.

```

Phase 4 — Important Files
Prompt

```text
Identify the most important files in this repository.

Rank them from most critical to least critical.

For each file explain:

- Why it exists
- What it controls
- Who depends on it
- Risks of changing it
- Whether it is safe to modify

Also identify:

- Global configuration
- Shared abstractions
- Common utilities
- Application entry points
- Startup configuration
- Environment configuration

Return as a table.

```

Phase 5 — Architecture Deep Dive
Prompt

```text
Now explain the architecture like you are teaching a new engineer.

Include:

- Overall architecture
- Design patterns
- Domain-driven structure (if any)
- Layer responsibilities
- Data flow
- Request lifecycle
- Dependency flow
- Business logic flow

Explain:

How a request travels from

Client

↓

Router

↓

Middleware

↓

Controller

↓

Service

↓

Repository

↓

Database

↓

Response

Use diagrams wherever useful.

```

Phase 6 — Dependency Analysis
Prompt

```text
Analyze dependencies.

Create a dependency graph.

Show:

Frontend

↓

Backend

↓

Application Layer

↓

Business Layer

↓

Infrastructure

↓

Database

↓

External APIs

Identify:

- Circular dependencies
- Tight coupling
- High-risk modules
- Shared modules
- Opportunities for refactoring

Do NOT change code.

```

Phase 7 — Code Quality Audit
Prompt

```text
Perform a Staff Engineer level code review of this repository.

Find:

- Code smells
- Dead code
- Duplicate code
- Large functions
- Large classes
- Tight coupling
- High complexity
- Poor abstractions
- Performance bottlenecks
- Security concerns
- Memory issues
- Race conditions
- Thread safety issues
- Technical debt
- Missing tests

Rank every issue:

Critical

High

Medium

Low

Do NOT fix anything.
Only produce an audit report.

```

Phase 8 — Wait for Ticket
Prompt

```text
Do NOT implement anything until I provide a feature request or Jira ticket.

When I provide the ticket:

1. Read it carefully.
2. Explain the problem.
3. Explain the business objective.
4. Identify affected modules.
5. Identify affected files.
6. Find similar implementations.
7. Explain implementation options.
8. Compare approaches.
9. Recommend the cleanest approach.

Wait for my approval before writing code.

```

Phase 9 — Ticket Analysis
Prompt

```text
Here is my ticket.

Before writing code:

Explain:

- Business problem
- Technical problem
- Existing implementation
- Related modules
- Related services
- Related APIs
- Related models

Identify:

- Files to modify
- Files to avoid
- Shared code to reuse
- Existing utilities
- Existing patterns

Estimate:

- Complexity
- Risk
- Time required

List:

- Edge cases
- Security concerns
- Performance concerns
- Scalability concerns
- Backward compatibility concerns

Do NOT write code yet.

Wait for my approval.

```

Phase 10 — Implementation Plan
Prompt

```text
Create a complete implementation plan.

Include:

Step-by-step tasks.

For each step explain:

- Why it is needed
- Which files change
- Expected outcome

Show dependencies between tasks.

Explain rollback strategy.

Explain testing strategy.

Wait for approval before implementing.

```

Phase 11 — Feature Implementation
Prompt

```text
Now implement the approved solution.

Requirements:

- Follow existing coding style exactly.
- Reuse existing abstractions.
- Do not duplicate code.
- Keep changes minimal.
- Keep functions small.
- Keep classes cohesive.
- Handle errors correctly.
- Add logging where appropriate.
- Avoid unnecessary comments.
- Maintain backward compatibility.
- Follow SOLID principles.
- Follow repository conventions.
- Do not introduce unnecessary dependencies.

After implementation provide:

- Summary
- Files changed
- Reason for each change
- Any assumptions
- Potential risks

```

Phase 12 — Unit Tests
Prompt

```text
Write comprehensive unit tests.

Cover:

- Happy paths
- Edge cases
- Invalid input
- Failure cases
- Exceptions
- Boundary values

Reuse existing testing patterns.

Do not rewrite existing tests unnecessarily.

```

Phase 13 — Self Code Review
Prompt

```text
Review your own implementation as if you are the senior reviewer.

Check:

- Bugs
- Logic errors
- Edge cases
- Security
- Race conditions
- Null handling
- Exception handling
- Performance
- Scalability
- Readability
- Maintainability
- Naming
- Consistency
- Test coverage

Would this PR be approved?

If not,

list improvements before finalizing.

```

Phase 14 — Final Verification
Prompt

```text
Before considering this task complete:

Verify:

✓ Project builds

✓ Formatting passes

✓ Lint passes

✓ Unit tests pass

✓ Integration tests pass

✓ No breaking changes

✓ No unused imports

✓ No dead code

✓ No unnecessary complexity

✓ Backward compatibility maintained

Provide a deployment checklist.

Provide release notes.

Provide a final implementation summary.

```

Phase 15 — Pull Request Review
Prompt

```text
Prepare this change for a production Pull Request.

Provide:

## Summary

## Business Value

## Technical Changes

## Files Modified

## Testing Performed

## Risks

## Rollback Plan

## Deployment Notes

## Reviewer Notes

## Follow-up Tasks

Also suggest a professional PR title and PR description.

```

Bonus Prompt — Think Like the Original Architect

```text
Think like the original architect of this repository.

Before writing code, explain:

- Why this architecture exists.
- Which coding conventions must be respected.
- Which abstractions should be reused.
- Which files should almost never be modified.
- Which design principles are followed.
- What would make a senior reviewer reject this Pull Request.
- What implementation mistakes junior engineers usually make in this repository.

Only after fully understanding the project should implementation begin.

```

Golden Rules

* Understand before coding.
* Reuse existing code whenever possible.
* Prefer minimal changes over broad refactors.
* Follow the repository's established architecture and conventions.
* Ask for clarification instead of making assumptions.
* Always create an implementation plan before writing code.
* Test thoroughly before considering the task complete.
* Review your own work with the same rigor as a senior reviewer.
* Optimize for maintainability, readability, and long-term stability.
Recommended Workflow

```
Clone Repository
        │
        ▼
Phase 1 → Repository Analysis
        │
        ▼
Phase 2 → Onboarding Guide
        │
        ▼
Phase 3 → Repository Map
        │
        ▼
Phase 4 → Important Files
        │
        ▼
Phase 5 → Architecture Deep Dive
        │
        ▼
Phase 6 → Dependency Analysis
        │
        ▼
Phase 7 → Code Quality Audit
        │
        ▼
Receive Ticket
        │
        ▼
Phase 8 → Ticket Analysis
        │
        ▼
Phase 9 → Implementation Plan
        │
        ▼
Approve Plan
        │
        ▼
Phase 10 → Implementation
        │
        ▼
Phase 11 → Unit Tests
        │
        ▼
Phase 12 → Self Review
        │
        ▼
Phase 13 → Final Verification
        │
        ▼
Phase 14 → Pull Request
        │
        ▼
Merge

```
