// SPDX-License-Identifier: GPL-3.0-or-later
//! Hard-capped byte budget for pipeline buffers.
//!
//! [`Budget`] hands out [`Grant`]s; dropping a grant returns its bytes. An
//! allocation past the cap is [`BudgetError`], never a crash. The pipeline
//! pairs a grant with each frame it allocates; this crate only counts bytes,
//! it never sees pixels.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

use std::fmt;
use std::sync::{Arc, Mutex};

/// Byte budget with a hard cap, shared across threads.
#[derive(Debug)]
pub struct Budget {
    /// Maximum live bytes.
    cap: u64,
    /// Currently granted bytes.
    used: Mutex<u64>,
}

/// Proof that `bytes` were charged against a [`Budget`].
///
/// Dropping the grant returns the bytes. Grants borrow their budget, so a
/// frame paired with its grant cannot outlive the budget it was charged to.
#[derive(Debug)]
pub struct Grant<'a> {
    budget: &'a Budget,
    bytes: u64,
}
/// Proof that `bytes` were charged against a shared [`Budget`].
///
/// Same promise as [`Grant`], but the budget travels as an [`Arc`] instead
/// of a borrow: a cached plane and a returned frame can each hold bytes past
/// the call that charged them, and the last dropped grant returns the bytes.
/// The pipeline pairs one of these with every frame it owns.
#[derive(Debug)]
pub struct SharedGrant {
    budget: Arc<Budget>,
    bytes: u64,
}

/// An allocation the [`Budget`] refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BudgetError {
    /// Bytes the caller asked for (including what is already used).
    pub requested_total: u64,
    /// Bytes still free.
    pub remaining: u64,
    /// The cap that refused.
    pub cap: u64,
}

impl fmt::Display for BudgetError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "memory budget exceeded: need {} bytes with {} already used, {} left of {} cap",
            self.requested_total,
            self.cap - self.remaining,
            self.remaining,
            self.cap,
        )
    }
}

impl std::error::Error for BudgetError {}

impl Budget {
    /// A budget holding at most `cap_bytes` live bytes.
    #[must_use]
    pub fn new(cap_bytes: u64) -> Self {
        Self {
            cap: cap_bytes,
            used: Mutex::new(0),
        }
    }

    /// The cap.
    #[must_use]
    pub fn cap(&self) -> u64 {
        self.cap
    }

    /// Currently granted bytes.
    #[must_use]
    pub fn used(&self) -> u64 {
        *self
            .used
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// Bytes still grantable.
    #[must_use]
    pub fn remaining(&self) -> u64 {
        self.cap.saturating_sub(self.used())
    }

    /// Charges `bytes` against the budget.
    ///
    /// A zero-byte grant always succeeds and releases nothing on drop.
    ///
    /// # Errors
    ///
    /// [`BudgetError`] when `bytes` past the used total would exceed the cap
    /// (or overflow `u64`, which is treated the same way: ungrantable).
    pub fn acquire(&self, bytes: u64) -> Result<Grant<'_>, BudgetError> {
        let mut used = self.charge(bytes)?;
        *used += bytes;
        Ok(Grant {
            budget: self,
            bytes,
        })
    }

    /// Charges `bytes` against a shared budget, returning an owned grant.
    ///
    /// Same accounting as [`Budget::acquire`]; the grant holds an [`Arc`] to
    /// the budget so it can outlive the call that charged it. Dropping the
    /// last grant for charged bytes returns them.
    ///
    /// # Errors
    ///
    /// [`BudgetError`] under the same condition as [`Budget::acquire`].
    pub fn acquire_shared(self: &Arc<Self>, bytes: u64) -> Result<SharedGrant, BudgetError> {
        let mut used = self.charge(bytes)?;
        *used += bytes;
        Ok(SharedGrant {
            budget: Arc::clone(self),
            bytes,
        })
    }

    /// Locks the used counter and refuses `bytes` past the cap. The caller
    /// adds `bytes` to the returned guard while still holding the lock.
    fn charge(&self, bytes: u64) -> Result<std::sync::MutexGuard<'_, u64>, BudgetError> {
        let used = self
            .used
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let remaining = self.cap.saturating_sub(*used);
        if bytes > remaining {
            return Err(BudgetError {
                requested_total: used.saturating_add(bytes),
                remaining,
                cap: self.cap,
            });
        }
        Ok(used)
    }

    /// Returns `bytes` to the budget; saturates rather than underflowing.
    fn release(&self, bytes: u64) {
        let mut used = self
            .used
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        *used = used.saturating_sub(bytes);
    }
}

impl Grant<'_> {
    /// Bytes this grant holds.
    #[must_use]
    pub fn bytes(&self) -> u64 {
        self.bytes
    }
}

impl Drop for Grant<'_> {
    fn drop(&mut self) {
        self.budget.release(self.bytes);
    }
}

impl SharedGrant {
    /// Bytes this grant holds.
    #[must_use]
    pub fn bytes(&self) -> u64 {
        self.bytes
    }
}

impl Drop for SharedGrant {
    fn drop(&mut self) {
        self.budget.release(self.bytes);
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{Budget, BudgetError};

    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }

    #[test]
    fn acquire_charges_and_drop_returns() {
        let budget = Budget::new(100);
        assert_eq!((budget.used(), budget.remaining()), (0, 100));
        let grant = budget.acquire(60).unwrap();
        assert_eq!(grant.bytes(), 60);
        assert_eq!((budget.used(), budget.remaining()), (60, 40));
        drop(grant);
        assert_eq!((budget.used(), budget.remaining()), (0, 100));
    }

    #[test]
    fn over_cap_is_an_error_not_a_crash() {
        let budget = Budget::new(100);
        let first = budget.acquire(60).unwrap();
        let err = budget.acquire(41).unwrap_err();
        assert_eq!(
            err,
            BudgetError {
                requested_total: 101,
                remaining: 40,
                cap: 100
            }
        );
        assert!(err.to_string().contains("memory budget exceeded"));
        assert!(err.to_string().contains("101"));
        // The failed acquire charged nothing.
        assert_eq!(budget.used(), 60);
        drop(first);
        // Exact fit works.
        let _full = budget.acquire(100).unwrap();
        assert_eq!(budget.remaining(), 0);
    }

    #[test]
    fn zero_grant_costs_nothing_and_overflow_is_refused() {
        let budget = Budget::new(100);
        let zero = budget.acquire(0).unwrap();
        assert_eq!(budget.used(), 0);
        drop(zero);
        assert_eq!(budget.used(), 0);
        let tiny = Budget::new(u64::MAX);
        let _all = tiny.acquire(u64::MAX).unwrap();
        assert!(tiny.acquire(1).is_err());
    }

    #[test]
    fn grants_are_shared_across_threads() {
        let budget = Budget::new(1_000);
        std::thread::scope(|scope| {
            for _ in 0..8 {
                scope.spawn(|| {
                    for _ in 0..50 {
                        let grant = budget.acquire(10).unwrap();
                        assert!(budget.used() <= 1_000);
                        drop(grant);
                    }
                });
            }
        });
        assert_eq!(budget.used(), 0);
    }

    #[test]
    fn shared_grant_outlives_its_call_and_returns_on_drop() {
        use std::sync::Arc;
        let budget = Arc::new(Budget::new(100));
        let grant = budget.acquire_shared(60).unwrap();
        assert_eq!(grant.bytes(), 60);
        assert_eq!(budget.used(), 60);
        // The grant owns its budget link: the bytes stay charged while the
        // grant lives, whatever happens to other handles to the budget.
        let again = Arc::clone(&budget);
        drop(budget);
        assert_eq!(again.used(), 60);
        drop(grant);
        assert_eq!(again.used(), 0);
    }

    #[test]
    fn shared_acquire_past_cap_reports_same_numbers() {
        use std::sync::Arc;
        let budget = Arc::new(Budget::new(100));
        let _first = budget.acquire_shared(60).unwrap();
        let err = budget.acquire_shared(41).unwrap_err();
        assert_eq!(
            err,
            BudgetError {
                requested_total: 101,
                remaining: 40,
                cap: 100
            }
        );
        assert_eq!(budget.used(), 60);
    }
}
