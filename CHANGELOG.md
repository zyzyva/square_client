# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Webhook handling infrastructure with `SquareClient.WebhookHandler` behaviour
- `SquareClient.WebhookPlug` for automatic signature verification and event parsing
- Comprehensive webhook documentation in WEBHOOK.md
- Test helpers for webhook signature generation
- Support for all major Square webhook event types

### Changed
- Enhanced README with webhook integration guide
- Improved test coverage with `capture_log` to prevent log leaks

### Fixed
- Test output now clean with proper log capture

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