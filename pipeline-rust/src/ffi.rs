/*
 * ffi.rs — safe Rust wrappers around the C++ matrix library (libcppmatrix).
 *
 * Memory contract
 * ---------------
 * Two allocation strategies are exposed:
 *
 * 1. Zero-copy (caller-owned output):
 *    Rust allocates a Vec<f64> for the result, then passes a raw pointer into
 *    its backing store to the C++ function.  C++ writes directly into Rust-
 *    owned memory — no intermediate copy is made, and deallocation follows
 *    the normal Vec drop path.
 *
 * 2. C++-owned allocation (CppMatrix):
 *    mat_multiply_alloc allocates via malloc inside the C++ translation unit.
 *    The pointer is wrapped in CppMatrix, whose Drop implementation calls
 *    mat_free (which calls free() in the same C++ TU) to release the memory.
 *    This pairing is mandatory: the allocator and deallocator must match.
 */

/* This module exposes a library-style bridge; not every function is wired to
 * an HTTP handler in main.rs.  Suppress dead_code lints for the whole module. */
#![allow(dead_code)]

use std::slice;

/* Link against the static archive produced by build.rs. */
#[link(name = "cppmatrix", kind = "static")]
unsafe extern "C" {
    /*
     * Zero-copy multiply: caller provides the output buffer.
     * out must point to at least m*n initialised (or zero) f64 values.
     */
    fn mat_multiply(
        a: *const f64,
        m: i32,
        k: i32,
        b: *const f64,
        n: i32,
        out: *mut f64,
    );

    /*
     * Zero-copy covariance: caller provides the output buffer.
     * out_cov must point to at least assets*assets f64 values.
     */
    fn covariance_matrix(
        returns: *const f64,
        assets: i32,
        periods: i32,
        out_cov: *mut f64,
    );

    /*
     * C++-owned allocation: returns a malloc'd pointer.
     * The caller MUST release it with mat_free.
     * Returns null on allocation failure or invalid dimensions.
     */
    fn mat_multiply_alloc(
        a: *const f64,
        m: i32,
        k: i32,
        b: *const f64,
        n: i32,
    ) -> *mut f64;

    /* Releases a pointer obtained from mat_multiply_alloc. */
    fn mat_free(ptr: *mut f64);

    /*
     * Cholesky decomposition: L * L^T = A.
     * A must be symmetric positive-definite, shape [n x n], row-major.
     * l_out must be caller-allocated, size [n x n].
     * Returns 0 on success, -1 if A is not positive-definite.
     */
    fn cholesky_decompose(a: *const f64, n: i32, l_out: *mut f64) -> i32;

    /*
     * Matrix-vector product: y = A * x.
     * A: row-major [m x n], x: length n, y: caller-allocated length m.
     */
    fn mat_vec_mul(
        a: *const f64,
        m: i32,
        n: i32,
        x: *const f64,
        y: *mut f64,
    );

    /*
     * Portfolio variance: scalar v = w^T * cov * w.
     * cov: row-major [assets x assets], weights: length assets.
     */
    fn portfolio_variance(
        cov: *const f64,
        weights: *const f64,
        assets: i32,
    ) -> f64;

    /*
     * Frobenius norm: sqrt( sum_{i,j} A[i,j]^2 ).
     * a: row-major [m x n].
     */
    fn mat_frobenius_norm(a: *const f64, m: i32, n: i32) -> f64;
}

/* ── CppMatrix — RAII wrapper for C++-allocated result buffers ─────────── */

/// Owns a matrix buffer allocated by mat_multiply_alloc.
/// The buffer is released via mat_free when this value is dropped.
#[allow(dead_code)]
pub struct CppMatrix {
    ptr: *mut f64,
    rows: usize,
    cols: usize,
}

impl CppMatrix {
    /// Returns a shared slice over the underlying data in row-major order.
    pub fn as_slice(&self) -> &[f64] {
        /* SAFETY: ptr is non-null (checked at construction), points to a
         * malloc'd region of rows*cols f64 values, and is valid for the
         * lifetime of self. */
        unsafe { slice::from_raw_parts(self.ptr, self.rows * self.cols) }
    }

    pub fn rows(&self) -> usize {
        self.rows
    }

    pub fn cols(&self) -> usize {
        self.cols
    }
}

impl Drop for CppMatrix {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            /* SAFETY: ptr was obtained from mat_multiply_alloc (malloc),
             * mat_free calls free() in the same C++ TU, and drop is called
             * exactly once by Rust's ownership system. */
            unsafe { mat_free(self.ptr) };
            self.ptr = std::ptr::null_mut();
        }
    }
}

/* CppMatrix does not implement Clone on purpose: copying C-heap memory
 * manually would require unsafe and a second allocation.  Callers that need
 * an owned copy should use multiply_zero_copy instead. */

/* SAFETY: CppMatrix owns its allocation exclusively.  No shared mutable
 * access is possible, so Send is safe. */
unsafe impl Send for CppMatrix {}

/* ── Public safe API ───────────────────────────────────────────────────── */

/// Computes C = A * B.  Rust allocates and owns the output Vec<f64>.
///
/// # Panics
/// Panics if any dimension is non-positive or if dimension products overflow
/// usize (which would require > 2^63 elements — not practically reachable).
pub fn multiply_zero_copy(a: &[f64], m: i32, k: i32, b: &[f64], n: i32) -> Vec<f64> {
    assert!(m > 0 && k > 0 && n > 0, "matrix dimensions must be positive");
    assert_eq!(a.len(), (m * k) as usize, "a length mismatch");
    assert_eq!(b.len(), (k * n) as usize, "b length mismatch");

    let mut out = vec![0.0_f64; (m * n) as usize];

    /* SAFETY: all pointers are valid, non-overlapping, and sized correctly.
     * C++ writes into out's backing store; no memory is allocated in C++. */
    unsafe {
        mat_multiply(a.as_ptr(), m, k, b.as_ptr(), n, out.as_mut_ptr());
    }

    out
}

/// Computes C = A * B.  The result buffer is allocated by C++ (malloc).
/// Returns a CppMatrix that calls mat_free on drop.
///
/// # Panics
/// Panics if any dimension is non-positive.
///
/// # Errors
/// Returns None if the C++ allocator returns a null pointer.
pub fn multiply_alloc(a: &[f64], m: i32, k: i32, b: &[f64], n: i32) -> Option<CppMatrix> {
    assert!(m > 0 && k > 0 && n > 0, "matrix dimensions must be positive");
    assert_eq!(a.len(), (m * k) as usize, "a length mismatch");
    assert_eq!(b.len(), (k * n) as usize, "b length mismatch");

    /* SAFETY: pointers are valid and correctly sized. */
    let ptr = unsafe { mat_multiply_alloc(a.as_ptr(), m, k, b.as_ptr(), n) };

    if ptr.is_null() {
        None
    } else {
        Some(CppMatrix {
            ptr,
            rows: m as usize,
            cols: n as usize,
        })
    }
}

/// Computes the sample covariance matrix of a returns matrix.
/// Rust allocates and owns the output Vec<f64>.
///
/// # Parameters
/// - `returns`: row-major matrix of shape `[assets x periods]`
/// - `assets`:  number of return series (rows)
/// - `periods`: number of observations per series (cols); must be >= 2
///
/// # Panics
/// Panics if dimensions are invalid.
pub fn covariance(returns: &[f64], assets: i32, periods: i32) -> Vec<f64> {
    assert!(assets > 0 && periods >= 2, "assets > 0 and periods >= 2 required");
    assert_eq!(returns.len(), (assets * periods) as usize, "returns length mismatch");

    let mut cov = vec![0.0_f64; (assets * assets) as usize];

    /* SAFETY: all pointers are valid and correctly sized. */
    unsafe {
        covariance_matrix(
            returns.as_ptr(),
            assets,
            periods,
            cov.as_mut_ptr(),
        );
    }

    cov
}

/// Computes the Cholesky factor L such that A = L * L^T.
/// A must be symmetric positive-definite, shape [n x n], row-major.
/// Rust allocates and owns the output Vec<f64>.
///
/// # Returns
/// `Some(l)` on success; `None` if A is not positive-definite.
///
/// # Panics
/// Panics if n is non-positive or if `a.len() != n*n`.
pub fn cholesky(a: &[f64], n: i32) -> Option<Vec<f64>> {
    assert!(n > 0, "n must be positive");
    assert_eq!(a.len(), (n * n) as usize, "a length mismatch for cholesky");

    let mut l = vec![0.0_f64; (n * n) as usize];

    /* SAFETY: a and l are correctly sized, non-overlapping Rust allocations. */
    let rc = unsafe { cholesky_decompose(a.as_ptr(), n, l.as_mut_ptr()) };

    if rc == 0 {
        Some(l)
    } else {
        None
    }
}

/// Computes y = A * x.  Rust allocates and owns the output Vec<f64>.
///
/// # Panics
/// Panics if dimensions are non-positive or lengths do not match.
pub fn mat_vec_multiply(a: &[f64], m: i32, n: i32, x: &[f64]) -> Vec<f64> {
    assert!(m > 0 && n > 0, "dimensions must be positive");
    assert_eq!(a.len(), (m * n) as usize, "a length mismatch");
    assert_eq!(x.len(), n as usize, "x length mismatch");

    let mut y = vec![0.0_f64; m as usize];

    /* SAFETY: all pointers are valid, non-overlapping, and correctly sized. */
    unsafe {
        mat_vec_mul(a.as_ptr(), m, n, x.as_ptr(), y.as_mut_ptr());
    }

    y
}

/// Computes the scalar portfolio variance v = w^T * cov * w.
/// An internal temporary buffer is allocated and freed inside C++.
///
/// # Panics
/// Panics if assets is non-positive or if lengths do not match.
pub fn portfolio_var(cov: &[f64], weights: &[f64], assets: i32) -> f64 {
    assert!(assets > 0, "assets must be positive");
    assert_eq!(cov.len(), (assets * assets) as usize, "cov length mismatch");
    assert_eq!(weights.len(), assets as usize, "weights length mismatch");

    /* SAFETY: pointers are valid and correctly sized; C++ allocates and frees
     * its own internal tmp buffer before returning the scalar result. */
    unsafe { portfolio_variance(cov.as_ptr(), weights.as_ptr(), assets) }
}

/// Computes the Frobenius norm: sqrt( sum_{i,j} A[i,j]^2 ).
///
/// # Panics
/// Panics if dimensions are non-positive or length does not match.
pub fn frobenius_norm(a: &[f64], m: i32, n: i32) -> f64 {
    assert!(m > 0 && n > 0, "dimensions must be positive");
    assert_eq!(a.len(), (m * n) as usize, "a length mismatch");

    /* SAFETY: pointer is valid and correctly sized; C++ is read-only. */
    unsafe { mat_frobenius_norm(a.as_ptr(), m, n) }
}
