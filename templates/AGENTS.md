# Pimcore Development Environment

This file is seeded once by the Pimcore dev runtime and is intentionally not overwritten on restart.
You may edit and extend it for this development instance.

## Environment

- You are working directly inside a disposable but fully functional remote Pimcore development environment.
- The VS Code workspace is normally opened at `/var/www`.
- Pimcore application root: `/var/www/html`.
- Editable bundle repositories: `/var/www/bundles`.
- Persistent import/test files: `/var/data`, also available as `/var/www/data`.
- Runtime helper scripts: `/opt/aggro`.
- Git configuration: `/var/www/.gitconfig`.
- GitHub App runtime data: `/var/www/.config/aggro-github`.
- Run Pimcore CLI commands from `/var/www/html`, for example `bin/console ...`.
- PHP, Composer, Node.js/npm, MariaDB, Redis, RabbitMQ, OpenSearch, Mercure and Chromium are available in the environment.
- Do not create a parallel Docker environment unless explicitly requested.

## Repositories

- `/var/www/html` is the host application repository (`aggrosoft/pimcore-app` by default).
- Each directory below `/var/www/bundles` is an independent Git repository.
- The host application's `vendor/aggrosoft/*` entries for development bundles are symlinks to the matching repositories below `/var/www/bundles`.
- Before changing a bundle, inspect its repository and run `git status` there.
- Never reset, clean, stash, overwrite or otherwise discard unrelated working-copy changes unless explicitly requested.
- Commit and push from the individual bundle repository only.
- Modify the host application only when the task genuinely requires an application-level change.
- Use the other Aggrosoft Pimcore bundles as references for structure, naming, services, configuration, tests and Studio integration before introducing new patterns.

## Composer

- The host application owns the runtime dependency graph used by the running Pimcore instance.
- After a host `composer install` or `composer update`, run `pimcore-dev-link-bundles` so the editable bundle checkouts are linked back into `vendor/aggrosoft`.
- Bundle repositories are libraries and have their own development dependencies.
- Before running a bundle's PHP quality checks, run `pimcore-dev-bundle-deps` from the bundle repository.
- The helper installs the bundle's development dependencies and removes a generated `composer.lock` again when that repository does not track one.
- Do not add or upgrade dependencies unless the task requires it.
- If a bundle runtime dependency changes, update the host application's dependency graph when necessary; a bundle-local `vendor/` directory does not change what the running Pimcore application loads.

## Implementation

- Follow the installed Pimcore 2026.x and Symfony conventions and use supported APIs.
- Prefer Pimcore's intended extension points over core hacks, direct database manipulation or custom framework abstractions.
- Keep solutions as small and maintainable as practical. Do not add architecture for hypothetical future needs.
- Determine installed versions from the running application when relevant.
- Do not add unnecessary backwards compatibility for unsupported Pimcore versions.
- If requirements are ambiguous, inspect the existing implementation and neighboring bundles first.

## Pimcore Studio UI

- Studio screens should look and behave like native Pimcore Studio screens.
- Reuse Pimcore Studio components, layouts and interaction patterns whenever suitable components already exist.
- Before designing a new Studio screen or interaction, inspect comparable Pimcore screens and existing Aggrosoft bundle screens.
- Keep containers, cards, tabs, forms, tables, loading states, empty states, notifications and action placement consistent with Pimcore Studio.
- Avoid bespoke layout systems and unnecessary custom styling.
- User-facing labels should describe domain concepts, not internal implementation details.
- If a bundle contains an `assets/package.json`, use its existing npm scripts. For the current data bundle this means installing with `npm ci`, running type/tests, building, and packaging the Studio build when relevant.

## External integrations

- Integration environment variables contain development/test credentials for services such as WAREXO, Shirtnetwork and Shopware.
- Never print, log, expose or commit credentials or secret environment values.
- Never copy secrets into source files, fixtures or documentation.
- Before performing an operation that writes to an external system, verify from the configured endpoint that the target is clearly a development/test system.
- If the configured target appears to be production or cannot be identified safely, do not perform an external write without explicit user instruction.
- Read-only integration checks may use the configured development/test services when relevant to the task.

## Import and test files

- Use `/var/data` for CSVs, source exports and other manually supplied development data.
- The same directory is visible in the workspace as `/var/www/data`.
- Do not commit files from `/var/data` into bundle repositories.
- Prefer exercising the real import command/path against supplied test files instead of mocking file imports when an integration test is practical.

## Validation

- Do not stop after editing code.
- Run the affected bundle's existing PHP quality checks. Usually:
  - `pimcore-dev-bundle-deps`
  - `composer quality`
- For bundles with frontend assets, install the locked npm dependencies and run the relevant type checks, tests and production/package build.
- Run targeted tests first, then the full relevant quality suite where practical.
- Test the change through the running Pimcore application when it affects runtime behavior, data projection, commands, migrations, object classes or Studio UI.
- Apply relevant Doctrine migrations and idempotent object-model installers when the change requires them.
- After Composer changes in the host application, relink bundles with `pimcore-dev-link-bundles`.
- For Studio/UI changes, verify the real page in the running application.
- Chromium is available for browser smoke checks. Use the most suitable browser workflow available; a basic fallback is `chromium --headless --no-sandbox --dump-dom <url>`.
- Before declaring the task complete, state which tests, builds, commands and integration checks were run and whether they passed.
- If something could not be tested, state exactly what and why.

## Git workflow

- Make atomic, meaningful commits: one logical change per commit.
- Use clear commit messages.
- Do not rewrite published history, force-push, rebase other people's work or modify unrelated commits unless explicitly requested.
- Never push or merge to `main` unless the user explicitly instructs you to do so in the current task.
- Local commits and work on a task/feature branch are allowed when useful.
- Never commit secrets, credentials, environment values, imported source files or production configuration.
