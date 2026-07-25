//! Shared deterministic proptest driver for the wire-format property suites.
//!
//! Not a test target itself (only top-level files in `tests/` are compiled as
//! integration-test binaries), so every suite pulls it in with `mod support;`.

#![allow(dead_code)]

use proptest::strategy::Strategy;
use proptest::test_runner::{Config, RngAlgorithm, TestCaseError, TestError, TestRng, TestRunner};

/// Run `test` over `cases` generated inputs.
///
/// The runner is seeded from a fixed RNG rather than from entropy, so the same
/// inputs are generated on every run on every machine: a failure that CI finds
/// reproduces locally instead of vanishing on the next attempt. That is also
/// why failure persistence is off — the `proptest-regressions/` file exists to
/// replay a random seed, which a fixed seed already gives us, and it would
/// otherwise have the test harness write into the source tree.
pub fn check<S: Strategy>(
    cases: u32,
    strategy: S,
    test: impl Fn(S::Value) -> Result<(), TestCaseError>,
) {
    let mut runner = TestRunner::new_with_rng(
        Config {
            cases,
            failure_persistence: None,
            ..Config::default()
        },
        TestRng::deterministic_rng(RngAlgorithm::ChaCha),
    );
    match runner.run(&strategy, test) {
        Ok(()) => {}
        Err(TestError::Fail(reason, input)) => {
            panic!("property failed: {reason}\nminimal failing input: {input:?}")
        }
        Err(e) => panic!("{e}"),
    }
}
