# Contributing

## Requirements

- The Xcode version [mentioned in the README](./README.md#requirements)
- [Mint](https://github.com/yonaskolb/Mint) package manager
- Node.js (any recent version should be fine)

## Setup

1. `mint bootstrap` — this will take quite a long time (~5 minutes on my machine) the first time you run it
2. `npm install`

## Running the tests

Either:

- `swift test`, or
- open `AblyChat.xcworkspace` in Xcode and test the `AblyChat` scheme

## Linting

To check formatting and code quality, run `swift run BuildTool lint`. Run with `--fix` to first automatically fix things where possible.

## Development guidelines

- The aim of the [example app](README.md#example-app) is that it demonstrate all of the core functionality of the SDK. So if you add a new feature, try to add something to the example app to demonstrate this feature.
- We should aim to make it easy for consumers of the SDK to be able to mock out the SDK in the tests for their own code. A couple of things that will aid with this:
  - Describe the SDK’s functionality via protocols (when doing so would still be sufficiently idiomatic to Swift).
  - When defining a `struct` that is emitted by the public API of the library, make sure to define a public memberwise initializer so that users can create one to be emitted by their mocks. (There is no way to make Swift’s autogenerated memberwise initializer public, so you will need to write one yourself. In Xcode, you can do this by clicking at the start of the type declaration and doing Editor → Refactor → Generate Memberwise Initializer.)
- When writing code that implements behaviour specified by the Chat SDK features spec, add a comment that references the identifier of the relevant spec item.

### Testing guidelines

#### Exposing test-only APIs

When writing unit tests, there are times that we need to access internal state of a type. To enable this, we might expose this state at an `internal` access level so that it can be used by the unit tests. However, we want to make it clear that this state is being exposed _purely_ for the purposes of testing that class, and that it should not be used by other components of the SDK.

So, when writing an API which has `internal` access level purely to enable it to be called by the tests, prefix this API’s name with `testOnly_`. For example:

```swift
private nonisolated let realtime: RealtimeClient

#if DEBUG
    internal nonisolated var testsOnly_realtime: RealtimeClient {
        realtime
    }
#endif
```

A couple of notes:

- Using a naming convention will allow us to verify that APIs marked `testsOnly` are not being used inside the SDK; we’ll do this in #70.
- I believe that we should be able to eliminate the boilerplate of re-exposing a `private` member as a `testsOnly` member (as exemplified above) using a macro (called e.g. `@ExposedToTests`), but my level of experience with macros is insufficient to be confident about being able to do this quickly, so have deferred it to #71.

#### Attributing tests to a spec point

When writing a test that relates to a spec point from the Chat SDK features spec, add a comment that contains one of the following tags:

- `@spec <spec-item-id>` — The test case directly tests all the functionality documented in the spec item.
- `@specOneOf(m/n) <spec-item-id>` — The test case is the m<sup>th</sup> of n test cases which, together, test all the functionality documented in the spec item.
- `@specPartial <spec-item-id>` — The test case tests some, but not all, of the functionality documented in the spec item. This is different to `@specOneOf` in that it implies that the test suite does not fully test this spec item.

The `<spec-item-id>` parameter should be a spec item identifier such as `CHA-RL3g`.

Each of the above tags can optionally be followed by a hyphen and an explanation of how the test relates to the given spec item.

Examples:

```swift
// @spec CHA-EX3f
func test1 { … }
```

```swift
// @specOneOf(1/2) CHA-EX2h — Tests the case where the room is FAILED
func test2 { … }

// @specOneOf(2/2) CHA-EX2h — Tests the case where the room is SUSPENDED
func test3 { … }
```

```swift
// @specPartial CHA-EX1h4 - Tests that we retry, but not the retry attempt limit because we’ve not implemented it yet
func test4 { … }
```

In [#46](https://github.com/ably-labs/ably-chat-swift/issues/46), we’ll write a script that uses these tags to generate a report about how much of the feature spec we’ve implemented.

#### Marking a spec point as untested

In addition to the above, you can add the following as a comment anywhere in the test suite:

- `@specUntested <spec-item-id> - <explanation>` — This indicates that the SDK implements the given spec point, but that there are no automated tests for it. This should be used sparingly; only use it when there is no way to test a spec point. It must be accompanied by an explanation of why this spec point is not tested.

Example:

```swift
// @specUntested CHA-EX2b - I was unable to find a way to test this spec point in an environment in which concurrency is being used; there is no obvious moment at which to stop observing the emitted state changes in order to be sure that FAILED has not been emitted twice.
```
