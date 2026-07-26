# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-07-26

### Added
- `SquareClient.Subscriptions.search/1` — search subscriptions by
  `:location_ids`, `:customer_ids`, and/or `:source_names`, auto-paginating
  through every page Square returns. Without webhooks, discovering and
  reconciling subscriptions requires listing them; no caller previously had
  a way to do that other than `get/2` by a known id.

## [0.3.0] - 2026-07-26

Consolidates all changes since 0.1.0 (an interim 0.2.0 version bump in
`mix.exs` was never cut as a changelog release).

### Added
- One-time payment support with `SquareClient.Payments.create_one_time/4` for time-based access
- Webhook handling infrastructure with `SquareClient.WebhookHandler` behaviour
- `SquareClient.WebhookPlug` for automatic signature verification and event parsing
- Comprehensive webhook documentation in WEBHOOK.md
- Test helpers for webhook signature generation
- Support for all major Square webhook event types
- Documentation for choosing between one-time purchases and subscriptions
- Automatic environment detection from the configured `api_url` — sandbox vs production plan IDs are selected by which Square URL is configured (explicit `SQUARE_ENVIRONMENT`/app-config overrides still win)
- Hosted subscription checkout links via `SquareClient.Checkout` (catalog-sourced pricing, explicit location required)

### Changed
- Enhanced README with webhook integration guide and one-time payment examples
- Improved test coverage with `capture_log` to prevent log leaks
- Apps configure `api_url` per environment (sandbox URL in dev, production URL in prod) and plan ID selection follows automatically; `Mix.env()`/`config_env()` are deliberately not used because neither is available at runtime in releases (see README "Environment Auto-Detection")
- Square mix tasks (`init_plans`, `list_plans`, `setup_plans`, `setup_production`, `cleanup_plans`) no longer boot the consuming application's supervision tree; they load code and configuration only, so task output is no longer buried under app log noise and no duplicate workers (e.g. Oban) are started alongside a running dev server

### Fixed
- Test output now clean with proper log capture
- Production deployments with the production `api_url` configured now correctly use production plan IDs; previously sandbox plan IDs could be used in production when `SQUARE_ENVIRONMENT` was not explicitly set
- Plan variations with a missing, nil, or empty-string currency now default to USD instead of sending a null currency that Square rejects
- `mix square.setup_plans` and `mix square.setup_production` now validate the entire plan definition (plan name; each active variation's name, cadence, and amount) before making any Square API call, and create nothing if anything is invalid. A mid-run Square API failure now stops the run, reports exactly which objects were created with their Square IDs, points at `mix square.cleanup_plans`, and exits with a failure status instead of printing a success banner

## [0.1.0] - 2025-01-26

### Added
- Initial release with Square API client functionality
- Direct REST API integration for payments and subscriptions
- Customer management (`SquareClient.Customers`)
- Payment processing (`SquareClient.Payments`)
- Subscription management (`SquareClient.Subscriptions`)
- Catalog operations (`SquareClient.Catalog`)
- Plan management with variations (`SquareClient.Plans`)
- Environment-aware configuration (sandbox/production)
- Comprehensive test suite with Bypass mocking
- Mix tasks for plan management

### Features
- Synchronous API calls for immediate feedback
- Flexible configuration via application config or environment variables
- Fast test execution (< 1 second)
- Support for Square API version 2025-01-23