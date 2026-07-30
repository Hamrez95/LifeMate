## Objective

<!-- What user, product or engineering outcome does this PR deliver? -->

## Scope

<!-- List the focused changes. Link the roadmap/issue. -->

Closes #

## Acceptance criteria

- [ ] User-visible behavior matches the linked issue
- [ ] Authorization/ownership/consent behavior is explicit
- [ ] Loading, empty, error, offline and retry states are considered where applicable
- [ ] No unrelated refactor or generated/local file is included

## Verification

- [ ] Relevant restore/dependency commands pass
- [ ] Static analysis and Release build pass
- [ ] Unit tests pass
- [ ] PostgreSQL/integration tests pass where backend or persistence changes
- [ ] Migration/model snapshot is clean where schema changes
- [ ] Real-device or end-to-end smoke test is documented where user flows change

Evidence:

<!-- Include workflow run, commands and concise results. -->

## Security, privacy and clinical boundary

- [ ] No secrets, tokens, credentials, signing files or personal/health data are committed or logged
- [ ] Cross-user isolation and post-revocation behavior are tested where relevant
- [ ] Flutter does not directly access healthcare tables
- [ ] Audit metadata excludes unnecessary health/free-text data
- [ ] No diagnosis, prescribing, emergency-response or drug-interaction claim is introduced

## Database and deployment

- [ ] No database change
- [ ] Database change has a reviewed migration, backup/restore plan and deployment order
- [ ] Environment variables and public client configuration are documented
- [ ] Production and test artifact boundaries are explicit

## Risks and rollback

Primary risks:

Rollback/forward-fix plan:

## Reviewer decision

- [ ] Diff is focused and understandable
- [ ] CI is green on the current head SHA
- [ ] No unresolved P0/P1 finding remains
- [ ] Documentation and runbooks match the implemented production path
