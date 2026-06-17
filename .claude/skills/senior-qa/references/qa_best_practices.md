# Senior QA Best Practices

Reference material for the `senior-qa` skill. Cite the section name when
applying a guideline in a reply.

## 1. The Test Pyramid (and when to invert it)

- **Unit** — fast, isolated, deterministic. Run on every save. Target: <1s
  per file, <10s for the suite up to medium codebases.
- **Integration** — module boundaries (HTTP handler ↔ DB, component ↔ store).
  Use real dependencies where cheap (in-memory SQLite, MSW). Target: <30s.
- **E2E** — full browser drive of the deployed app. Reserved for the top
  ~10 user journeys. Target: <5 min, parallelized.

Invert the pyramid only when the system's correctness lives mostly in
integration glue (Next.js server actions, RSC boundaries, webhooks). Then
integration becomes the widest band, with thinner unit and E2E tiers.

## 2. Test Selection Heuristics

Order risk by:

1. **Money paths** — checkout, billing, payouts, anything that moves value.
2. **Auth & authz** — login, role gates, token refresh, multi-tenancy.
3. **Data correctness** — migrations, currency, dates, totals, search.
4. **Critical UX** — onboarding, primary CRUD, anything in the top nav.
5. **Cross-cutting** — i18n, a11y, dark mode, mobile breakpoints.

Anything below tier 5 (visual polish, low-traffic pages) usually does not
deserve dedicated tests; lean on type checking and code review.

## 3. Anatomy of a Good Test

```ts
it("rejects a transfer when the source account is frozen", async () => {
  // Arrange
  const source = accountFactory.frozen();
  const dest = accountFactory.active();

  // Act
  const result = await transfer({ from: source, to: dest, amount: 100 });

  // Assert
  expect(result).toEqual({ ok: false, error: "ACCOUNT_FROZEN" });
});
```

Rules:

- **Name describes behavior**, not implementation. "rejects … when …" not
  "throws ACCOUNT_FROZEN".
- **One logical assertion** per test. Multiple `expect`s are fine if they
  describe one outcome.
- **No conditionals.** If a test has `if`, it's two tests.
- **No shared mutable setup.** Each test owns its data.

## 4. Selectors and Locators (E2E)

Stable, in order of preference:

1. ARIA role + accessible name — `getByRole("button", { name: /save/i })`.
2. Test IDs — `data-testid="checkout-submit"` on user-meaningful elements
   only, not on every div.
3. Visible text for body copy — `getByText("Welcome back")`.
4. CSS / nth selectors — **last resort**; they break on refactor.

Never rely on tag structure (`div > div > span:nth-child(2)`).

## 5. Flake Hunting Playbook

When a test flakes:

1. **Reproduce locally with `--repeat-each=20`** (Playwright) or `--runs=20`
   (custom loop). If it never flakes locally, you have an environment bug.
2. **Read the trace.** Playwright traces show the exact DOM at failure.
3. **Classify the cause:**
   - Race against async UI → use `await expect(locator).toHaveText(...)`,
     never `waitForTimeout`.
   - Time/clock dependency → freeze with `sinon.useFakeTimers` or
     Playwright's `page.clock`.
   - Shared state (DB, fixtures, env) → isolate per worker.
   - Network → mock via MSW or Playwright `route` interception.
4. **Fix at the root.** Adding retries hides the bug from you but ships it
   to users. Retries are only acceptable for genuinely external dependencies
   (third-party APIs, browser launch).

## 6. Coverage Interpretation

- **Line coverage > 0** is the bar for "this file is exercised at all".
- **Branch coverage** is where bugs hide; care about it for logic-heavy code.
- **100% coverage is a smell** — usually means tests assert on
  implementation, not behavior.
- Track **diff coverage** in CI (coverage of lines changed in the PR). It's
  the only number worth gating on.

## 7. CI Tiering

Three tiers, fail fast:

1. **Pre-commit / pre-push** — lint, type-check, unit tests for touched
   packages. Seconds.
2. **PR check** — full unit + integration + diff coverage + smoke E2E
   (5–10 critical specs). Minutes.
3. **Pre-deploy / nightly** — full E2E across browsers, visual regression,
   load tests. Tens of minutes.

Never put a 20-minute E2E suite on the PR-blocking path. Developers will
disable it.

## 8. Accessibility Coverage

- Run `axe-core` (`@axe-core/playwright` or `jest-axe`) on every page-level
  test. Fail on serious / critical violations.
- Cover keyboard navigation for any custom widget — modals, menus, combo
  boxes. `Tab`, `Shift+Tab`, `Esc`, `Enter`, arrow keys.
- Test with a screen reader at least once per major release, not via CI.

## 9. Security Smoke Tests

For any app with auth:

- Unauthenticated request to a protected endpoint → 401/redirect.
- Cross-tenant request (User A asking for User B's resource) → 403/404.
- Expired or tampered token → 401.
- CSRF token missing on a state-changing request → rejected.

These are five-line integration tests with disproportionate value.

## 10. React / Next.js Specifics

- Prefer **Testing Library** queries that mirror how users find elements;
  avoid `container.querySelector`.
- Test **behavior, not state.** Don't assert on hook internals; assert on
  what renders.
- For server components and server actions, integration-test through the
  HTTP layer or a Next.js test harness; don't try to unit-test them in
  isolation from Next's runtime.
- Snapshot tests are acceptable only for stable, small, presentational
  components. Inline-snapshot them so the diff lives next to the assertion.

## 11. Node.js Service Specifics

- Use **supertest** against the actual app instance, not a mocked router.
- Spin up the database for integration tests; transaction-rollback per test
  for speed and isolation.
- Contract-test outbound HTTP calls with Pact or recorded fixtures; don't
  let your service drift from its consumers.
- For background jobs, test the handler function directly and test the
  enqueue contract separately.

## 12. Reporting Findings

When summarizing a QA pass, structure the reply as:

1. **What I tested** — files / flows / endpoints.
2. **What I found** — failures, flakes, gaps, anti-patterns. Sorted by
   severity.
3. **What I changed** — files added/modified, coverage delta.
4. **What I'd do next** — explicit owner if known, otherwise a punch list.
