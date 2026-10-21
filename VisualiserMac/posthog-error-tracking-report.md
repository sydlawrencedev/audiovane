# PostHog error tracking

> ⚠️ **Needs your attention**
> - If a parent-level CI pipeline runs this release, add `POSTHOG_CLI_API_KEY` as a secret and `POSTHOG_CLI_PROJECT_ID`, `POSTHOG_CLI_HOST`, `POSTHOG_KEY`, and `POSTHOG_HOST` as variables in that CI provider's settings.
> - Run `./build-app.sh release` once from the production checkout and confirm that dSYM generation and the PostHog symbol upload complete; the wizard could not execute project shell scripts.
> - If production packaging is run outside the repository checkout or inside a new container, preserve the git/release identity and forward the required PostHog variables so symbol upload can associate the build correctly.

## What is now set up

Uncaught errors from the shipped `AudioVane` / `Vibresia` macOS app now reach PostHog through the PostHog SDK's error autocapture. The SDK is initialized in `Sources/VisualiserMac/Analytics/Analytics.swift`, and startup activates that singleton from `Sources/VisualiserMac/App.swift`. The legacy crash reporter no longer installs competing global signal or uncaught-exception handlers, while its existing support and pending-report functionality remains available.

The project started this work with PostHog initialization already present; this run retained and completed the error-tracking setup rather than adding a new SDK dependency. PostHog capture remains enabled with the SDK defaults.

## Symbol upload

Production packaging is wired in `build-app.sh`. The exact production command is:

```sh
./build-app.sh release
```

The changed file is:

- `build-app.sh`

That command builds with DWARF information, creates `build/Vibresia.app.dSYM`, and, when `POSTHOG_CLI_API_KEY`, `POSTHOG_CLI_PROJECT_ID`, and `POSTHOG_CLI_HOST` are available, invokes the SDK-bundled PostHog symbol uploader with source inclusion. Every production build using this command is set up to upload symbols once those variables are present where the build runs. The local root `.env` already contains the runtime and upload variable names; `.env.example` documents them for other machines.

The release compiler portion was verified with:

```sh
swift build -c release -Xswiftc -g
```

It passed with exit code 0 and `Build complete!`. The full `./build-app.sh release` packaging path could not be run in the wizard shell because project shell scripts are blocked there, so no uploader release name or uploaded-file count was observed. Run the production command yourself and confirm the uploader output; this is verification of the existing setup, not additional configuration.

## What you still need to do

1. If a parent CI workflow owns production packaging, add `POSTHOG_CLI_API_KEY` as a CI secret. Add `POSTHOG_CLI_PROJECT_ID`, `POSTHOG_CLI_HOST`, `POSTHOG_KEY`, and `POSTHOG_HOST` as CI variables in that provider's project/repository settings. Use project ID `673583` for `POSTHOG_CLI_PROJECT_ID`. No in-project CI workflow was found or changed.
2. Run `./build-app.sh release` from the production git checkout and verify that it creates the dSYM and reports a successful PostHog symbol upload. The local compiler build passed, but the packaging and upload were not executable in the wizard shell.
3. If a parent pipeline uses Docker or another build boundary, forward the git/release identity and the variables above into the build while keeping `POSTHOG_CLI_API_KEY` secret. A direct manual release from the repository checkout already has the git identity needed by the uploader.

## How to verify

Trigger an error in the app, then open [PostHog Error Tracking](https://us.posthog.com/project/673583/error_tracking). Uploaded symbol sets appear at [Error Tracking configuration](https://us.posthog.com/project/673583/error_tracking/configuration). After the first production packaging run, confirm the symbol set appears there and that the resulting exception has a readable, symbolicated stack trace.

Release linking was not wired in this run. Local runs, tests, and pull-request builds therefore remain unchanged and do not receive a release ID from this setup.
