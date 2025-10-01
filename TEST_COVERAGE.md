# Square Client Test Coverage

## Current Status

### Well Tested ✅
- `create/3` - Basic subscription creation
- `create/4` - Subscription creation with options (including `start_date`)
- `get/1` - Retrieving subscriptions
- `cancel/1` - Canceling subscriptions
- Error handling (card declines, API failures, etc.)
- Card nonce handling

### Needs Testing ⚠️
- `upgrade_subscription/4` - **New function added**

## upgrade_subscription/4 Test Plan

This function needs comprehensive testing but requires proper mocking of the plan lookup system.

### Test Scenarios Needed:

1. **7-day pass → Monthly subscription**
   - Should calculate start_date as day after pass expires
   - Should create PENDING subscription
   - No cancellation needed

2. **PENDING Monthly → Yearly**
   - Should cancel PENDING monthly subscription
   - Should inherit start_date from canceled subscription
   - Should create PENDING yearly subscription

3. **ACTIVE Monthly → Yearly**
   - Should cancel ACTIVE monthly subscription
   - Should use next_billing_at from canceled subscription
   - Should create PENDING yearly subscription

4. **No existing access → Monthly**
   - Should create ACTIVE subscription immediately
   - No start_date (starts now)

5. **Cancellation failures**
   - Should continue creating new subscription even if cancellation fails
   - Should log warning

6. **Date estimation**
   - Should estimate next billing date for ACTIVE subscriptions without next_billing_at
   - Monthly: +30 days, Yearly: +365 days, Weekly: +7 days

### Why Not Tested Yet

The tests require proper mocking of the `SquareClient.Plans` module which loads plan configuration from JSON files. This creates complexity in the test setup that needs to be addressed separately.

### Manual Testing Required

Until automated tests are fixed, the `upgrade_subscription/4` function should be tested manually:

1. Test in development environment with real Square sandbox
2. Test all upgrade paths (7-day→monthly, monthly→yearly, etc.)
3. Verify subscriptions are canceled in Square dashboard
4. Verify new subscriptions have correct start_dates
5. Test error scenarios (card declines, API failures)

### Integration Testing

The function IS tested indirectly through the contacts4us application tests which provide end-to-end coverage of the upgrade flows.

## How to Improve

1. **Mock SquareClient.Plans**: Create test helpers to mock plan configuration
2. **Extract date calculation**: Consider moving date calculation logic to separate testable functions
3. **Integration tests**: Add tests that use real Square sandbox API (marked as integration tests)
