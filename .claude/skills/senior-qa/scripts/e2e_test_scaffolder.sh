#!/usr/bin/env bash
#
# e2e_test_scaffolder.sh — generate a Playwright spec skeleton for a named
# user journey, plus a matching page-object stub.
#
# Creates:
#   e2e/<journey>.spec.ts
#   e2e/pages/<Journey>Page.ts   (if it doesn't already exist)
#   playwright.config.ts          (only if missing — minimal opinionated config)
#
# Usage:
#   scripts/e2e_test_scaffolder.sh "checkout flow" [--dir e2e] [--force]

set -euo pipefail

print_help() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_help
  exit 0
fi

JOURNEY=""
DIR="e2e"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) JOURNEY="$1"; shift ;;
  esac
done

if [[ -z "$JOURNEY" ]]; then
  echo "error: journey name required (e.g. \"checkout flow\")" >&2
  exit 2
fi

# Normalize names.
slug="$(echo "$JOURNEY" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
pascal="$(echo "$JOURNEY" | sed -E 's/[^a-zA-Z0-9]+/ /g' \
  | awk '{ for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print }' \
  | tr -d ' ')"

mkdir -p "$DIR/pages"

SPEC_PATH="$DIR/$slug.spec.ts"
POM_PATH="$DIR/pages/${pascal}Page.ts"
CONFIG_PATH="playwright.config.ts"

if [[ -e "$SPEC_PATH" && $FORCE -ne 1 ]]; then
  echo "error: $SPEC_PATH exists (pass --force to overwrite)" >&2
  exit 1
fi

cat > "$SPEC_PATH" <<EOF
import { test, expect } from "@playwright/test";
import { ${pascal}Page } from "./pages/${pascal}Page";

test.describe("${JOURNEY}", () => {
  test.beforeEach(async ({ page }) => {
    // TODO: replace with project's auth fixture (storageState) when ready.
    await page.goto("/");
  });

  test("happy path: user can complete the ${JOURNEY}", async ({ page }) => {
    const flow = new ${pascal}Page(page);
    await flow.start();
    await flow.complete();
    await expect(flow.successBanner).toBeVisible();
  });

  test("validation: surfaces a clear error on bad input", async ({ page }) => {
    const flow = new ${pascal}Page(page);
    await flow.start();
    await flow.submitWithInvalidInput();
    await expect(flow.errorMessage).toBeVisible();
  });

  test("authz: unauthenticated users are redirected to login", async ({
    browser,
  }) => {
    const ctx = await browser.newContext({ storageState: undefined });
    const page = await ctx.newPage();
    await page.goto("/${slug}");
    await expect(page).toHaveURL(/login/);
    await ctx.close();
  });
});
EOF

if [[ ! -e "$POM_PATH" || $FORCE -eq 1 ]]; then
  cat > "$POM_PATH" <<EOF
import { Page, Locator } from "@playwright/test";

export class ${pascal}Page {
  readonly page: Page;
  readonly successBanner: Locator;
  readonly errorMessage: Locator;

  constructor(page: Page) {
    this.page = page;
    this.successBanner = page.getByRole("status", { name: /success/i });
    this.errorMessage = page.getByRole("alert");
  }

  async start() {
    // TODO: navigate to the entry point of the ${JOURNEY}.
    await this.page.goto("/${slug}");
  }

  async complete() {
    // TODO: drive the happy-path interactions.
    throw new Error("not implemented");
  }

  async submitWithInvalidInput() {
    // TODO: trigger a validation failure.
    throw new Error("not implemented");
  }
}
EOF
fi

if [[ ! -e "$CONFIG_PATH" ]]; then
  cat > "$CONFIG_PATH" <<'EOF'
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: process.env.BASE_URL ?? "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
});
EOF
  echo "wrote $CONFIG_PATH"
fi

echo "wrote $SPEC_PATH"
[[ -e "$POM_PATH" ]] && echo "wrote $POM_PATH"
echo
echo "Next steps:"
echo "  1. Fill in the TODOs in ${pascal}Page — use role/text selectors."
echo "  2. Run: npx playwright test $SPEC_PATH --ui"
echo "  3. Add an auth fixture (storageState) once login is reusable."
