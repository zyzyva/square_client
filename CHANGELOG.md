# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- One-time payment support with `SquareClient.Payments.create_one_time/4` for time-based access
- Webhook handling infrastructure with `SquareClient.WebhookHandler` behaviour
- `SquareClient.WebhookPlug` for automatic signature verification and event parsing
- Comprehensive webhook documentation in WEBHOOK.md
- Test helpers for webhook signature generation
- Support for all major Square webhook event types
- Documentation for choosing between one-time purchases and subscriptions
- **Automatic environment detection from `config_env()` (Mix environment)**
- **Automatic API URL selection based on environment**

### Changed
- Enhanced README with webhook integration guide and one-time payment examples
- Improved test coverage with `capture_log` to prevent log leaks
- **Environment detection now auto-detects from `config_env()` - no configuration needed**
- **API URL auto-selected: production when `MIX_ENV=prod`, sandbox otherwise**
- **Updated documentation - users no longer need to configure `api_url` or `SQUARE_ENVIRONMENT`**

### Fixed
- Test output now clean with proper log capture
- **Production deployments now correctly use production plan IDs and API URL automatically**
- **Fixed issue where sandbox plan IDs were used in production when `SQUARE_ENVIRONMENT` was not explicitly set**

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