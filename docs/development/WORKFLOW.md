# Development workflow

1. Pick one versioned issue from the launch roadmap.
2. Create one focused feature branch.
3. Write acceptance criteria, abuse cases, UX states, and rollback notes before implementation.
4. Implement domain/data/API first where required.
5. Add unit and PostgreSQL integration tests, especially cross-user isolation.
6. Run the relevant CI workflow.
7. Review the change through product, architecture/security, UI/UX, visual, accessibility, reliability, privacy, and real-user-test critic gates.
8. Merge only when required checks are green and no P0 issue remains.
9. Apply verified migrations to Supabase after merge.
10. Validate on real Android devices before promoting a release.

Documentation-only commits may land directly on `main`; production code changes require a pull request and green CI.
