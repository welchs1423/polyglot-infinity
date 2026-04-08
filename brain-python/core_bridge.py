"""
core_bridge.py

FFI wrapper for the C++ shared library (libcore.so).

Exposes all symbols from calculator.cpp and matrix.cpp as a single
CoreBridge class.  Callers work entirely with Python lists and scalars;
no ctypes knowledge is needed outside this module.

C++ sources compiled into libcore.so:
  core-cpp/src/calculator.cpp  - extreme_computation, print_cpp_status
  core-cpp/src/matrix.cpp      - mat_multiply, mat_multiply_alloc, mat_free,
                                  covariance_matrix, cholesky_decompose,
                                  mat_vec_mul, portfolio_variance,
                                  mat_frobenius_norm
"""

import ctypes
import os
import time
from typing import List

# Default library path: libcore.so must reside next to this file.
_DEFAULT_LIB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "libcore.so")


class CoreBridgeError(RuntimeError):
    """Raised when a C++ function returns an error code or NULL."""


class CoreBridge:
    """
    Wrapper for the C++ shared library libcore.so.

    All methods accept ordinary Python lists of floats and return Python
    floats or lists.  Row-major flat lists represent matrices:
    element (i, j) of an [m x n] matrix M is stored at index i*n + j.

    Usage:
        bridge = CoreBridge()
        result = bridge.extreme_computation(1_000_000)
        cov = bridge.covariance_matrix(returns_flat, assets=4, periods=252)
    """

    def __init__(self, lib_path: str = _DEFAULT_LIB_PATH) -> None:
        """
        Load the shared library from lib_path and bind all function signatures.
        Raises OSError if the library cannot be found or loaded.
        """
        if not os.path.isfile(lib_path):
            raise OSError(f"Shared library not found: {lib_path}")

        self._lib = ctypes.CDLL(lib_path)
        self._bind_signatures()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _bind_signatures(self) -> None:
        """Declare argtypes and restype for every exported C symbol."""
        lib = self._lib
        _pdbl = ctypes.POINTER(ctypes.c_double)

        # calculator.cpp symbols
        lib.print_cpp_status.argtypes = []
        lib.print_cpp_status.restype = None

        lib.extreme_computation.argtypes = [ctypes.c_int]
        lib.extreme_computation.restype = ctypes.c_double

        # matrix.cpp symbols
        lib.mat_multiply.argtypes = [
            _pdbl, ctypes.c_int, ctypes.c_int,
            _pdbl, ctypes.c_int,
            _pdbl,
        ]
        lib.mat_multiply.restype = None

        lib.mat_multiply_alloc.argtypes = [
            _pdbl, ctypes.c_int, ctypes.c_int,
            _pdbl, ctypes.c_int,
        ]
        lib.mat_multiply_alloc.restype = _pdbl

        lib.mat_free.argtypes = [_pdbl]
        lib.mat_free.restype = None

        lib.covariance_matrix.argtypes = [
            _pdbl, ctypes.c_int, ctypes.c_int,
            _pdbl,
        ]
        lib.covariance_matrix.restype = None

        lib.cholesky_decompose.argtypes = [
            _pdbl, ctypes.c_int,
            _pdbl,
        ]
        lib.cholesky_decompose.restype = ctypes.c_int

        lib.mat_vec_mul.argtypes = [
            _pdbl, ctypes.c_int, ctypes.c_int,
            _pdbl,
            _pdbl,
        ]
        lib.mat_vec_mul.restype = None

        lib.portfolio_variance.argtypes = [
            _pdbl,
            _pdbl,
            ctypes.c_int,
        ]
        lib.portfolio_variance.restype = ctypes.c_double

        lib.mat_frobenius_norm.argtypes = [
            _pdbl, ctypes.c_int, ctypes.c_int,
        ]
        lib.mat_frobenius_norm.restype = ctypes.c_double

    @staticmethod
    def _to_c_array(data: List[float]) -> ctypes.Array:
        """
        Convert a Python float list to a ctypes c_double array.
        The returned object must remain alive for the duration of any C call
        that receives a pointer into it.
        """
        n = len(data)
        return (ctypes.c_double * n)(*data)

    @staticmethod
    def _ptr(arr: ctypes.Array) -> ctypes.POINTER:
        """Cast a ctypes array to POINTER(c_double) for use as a function argument."""
        return ctypes.cast(arr, ctypes.POINTER(ctypes.c_double))

    # ------------------------------------------------------------------
    # calculator.cpp wrappers
    # ------------------------------------------------------------------

    def print_status(self) -> None:
        """Print the C++ engine status message to stdout."""
        self._lib.print_cpp_status()

    def extreme_computation(self, iterations: int) -> float:
        """
        Run floating-point accumulation in C++ and return the cumulative sum.

        Formula per step: result += pi * i / (i + 1.0)
        iterations : number of loop steps (non-negative integer)
        Returns    : final accumulated value as a Python float
        """
        if iterations < 0:
            raise ValueError("iterations must be a non-negative integer")
        return float(self._lib.extreme_computation(ctypes.c_int(iterations)))

    # ------------------------------------------------------------------
    # matrix.cpp wrappers
    # ------------------------------------------------------------------

    def mat_multiply(
        self,
        a: List[float], m: int, k: int,
        b: List[float], n: int,
    ) -> List[float]:
        """
        Compute C = A * B using cache-tiled blocked multiplication.

        a : row-major flat list, length m*k  (A is m x k)
        m : rows of A
        k : shared inner dimension (cols of A, rows of B)
        b : row-major flat list, length k*n  (B is k x n)
        n : cols of B

        Returns a row-major flat list of length m*n representing C (m x n).
        """
        if len(a) != m * k:
            raise ValueError(
                f"Matrix A requires {m * k} elements for shape ({m}, {k}), got {len(a)}"
            )
        if len(b) != k * n:
            raise ValueError(
                f"Matrix B requires {k * n} elements for shape ({k}, {n}), got {len(b)}"
            )

        arr_a = self._to_c_array(a)
        arr_b = self._to_c_array(b)
        arr_c = (ctypes.c_double * (m * n))()

        self._lib.mat_multiply(
            self._ptr(arr_a), ctypes.c_int(m), ctypes.c_int(k),
            self._ptr(arr_b), ctypes.c_int(n),
            self._ptr(arr_c),
        )

        return list(arr_c)

    def mat_multiply_alloc(
        self,
        a: List[float], m: int, k: int,
        b: List[float], n: int,
    ) -> List[float]:
        """
        Same computation as mat_multiply, but the C++ side allocates the output
        buffer via malloc; this wrapper copies the result and frees the buffer
        via mat_free before returning.

        Prefer mat_multiply for repeated calls; this variant exercises the
        alloc/free path exposed by the library.
        """
        if len(a) != m * k:
            raise ValueError(
                f"Matrix A requires {m * k} elements for shape ({m}, {k}), got {len(a)}"
            )
        if len(b) != k * n:
            raise ValueError(
                f"Matrix B requires {k * n} elements for shape ({k}, {n}), got {len(b)}"
            )

        arr_a = self._to_c_array(a)
        arr_b = self._to_c_array(b)

        ptr = self._lib.mat_multiply_alloc(
            self._ptr(arr_a), ctypes.c_int(m), ctypes.c_int(k),
            self._ptr(arr_b), ctypes.c_int(n),
        )

        if not ptr:
            raise CoreBridgeError("mat_multiply_alloc returned NULL (allocation failure)")

        try:
            result = [float(ptr[i]) for i in range(m * n)]
        finally:
            # Always release the C-side buffer regardless of exceptions above.
            self._lib.mat_free(ptr)

        return result

    def covariance_matrix(
        self,
        returns: List[float],
        assets: int,
        periods: int,
    ) -> List[float]:
        """
        Compute the unbiased sample covariance matrix S where:
          S[i][j] = sum_{t}(r_it - mu_i)(r_jt - mu_j) / (T - 1)

        returns : row-major flat list, length assets*periods.
                  Row i contains the T-length return series for asset i.
        assets  : number of assets (rows of the returns matrix)
        periods : number of return observations per asset (columns); must be >= 2

        Returns a row-major flat list of length assets*assets.
        """
        if periods < 2:
            raise ValueError("periods must be >= 2 for an unbiased covariance estimate")
        if len(returns) != assets * periods:
            raise ValueError(
                f"returns requires {assets * periods} elements for "
                f"{assets} assets x {periods} periods, got {len(returns)}"
            )

        arr_r = self._to_c_array(returns)
        arr_cov = (ctypes.c_double * (assets * assets))()

        self._lib.covariance_matrix(
            self._ptr(arr_r), ctypes.c_int(assets), ctypes.c_int(periods),
            self._ptr(arr_cov),
        )

        return list(arr_cov)

    def cholesky_decompose(self, a: List[float], n: int) -> List[float]:
        """
        Compute the lower-triangular Cholesky factor L such that A = L * L^T.

        a : row-major flat list, length n*n.
            A must be symmetric positive-definite.
        n : matrix dimension

        Returns a row-major flat list of length n*n representing L.
        The upper triangle is zero; only the lower triangle carries values.

        Raises CoreBridgeError if A is not positive-definite.
        """
        if len(a) != n * n:
            raise ValueError(
                f"Matrix a requires {n * n} elements for shape ({n}, {n}), got {len(a)}"
            )

        arr_a = self._to_c_array(a)
        arr_l = (ctypes.c_double * (n * n))()

        rc = self._lib.cholesky_decompose(
            self._ptr(arr_a), ctypes.c_int(n),
            self._ptr(arr_l),
        )

        if rc != 0:
            raise CoreBridgeError(
                "cholesky_decompose failed: matrix is not symmetric positive-definite"
            )

        return list(arr_l)

    def mat_vec_mul(
        self,
        a: List[float], m: int, n: int,
        x: List[float],
    ) -> List[float]:
        """
        Compute y = A * x.

        a : row-major flat list, length m*n  (A is m x n)
        m : rows of A
        n : cols of A (must equal len(x))
        x : input vector, length n

        Returns output vector y as a list of length m.
        """
        if len(a) != m * n:
            raise ValueError(
                f"Matrix a requires {m * n} elements for shape ({m}, {n}), got {len(a)}"
            )
        if len(x) != n:
            raise ValueError(
                f"Vector x requires {n} elements to match matrix cols, got {len(x)}"
            )

        arr_a = self._to_c_array(a)
        arr_x = self._to_c_array(x)
        arr_y = (ctypes.c_double * m)()

        self._lib.mat_vec_mul(
            self._ptr(arr_a), ctypes.c_int(m), ctypes.c_int(n),
            self._ptr(arr_x),
            self._ptr(arr_y),
        )

        return list(arr_y)

    def portfolio_variance(
        self,
        cov: List[float],
        weights: List[float],
        assets: int,
    ) -> float:
        """
        Compute the scalar portfolio variance v = w^T * cov * w.

        cov     : row-major flat list, length assets*assets (covariance matrix)
        weights : portfolio weight vector, length assets
        assets  : number of assets

        Returns the portfolio variance as a Python float (>= 0).
        """
        if len(cov) != assets * assets:
            raise ValueError(
                f"cov requires {assets * assets} elements for {assets} assets, got {len(cov)}"
            )
        if len(weights) != assets:
            raise ValueError(
                f"weights requires {assets} elements, got {len(weights)}"
            )

        arr_cov = self._to_c_array(cov)
        arr_w = self._to_c_array(weights)

        return float(
            self._lib.portfolio_variance(
                self._ptr(arr_cov),
                self._ptr(arr_w),
                ctypes.c_int(assets),
            )
        )

    def mat_frobenius_norm(self, a: List[float], m: int, n: int) -> float:
        """
        Compute the Frobenius norm: sqrt(sum_{i,j} A[i,j]^2).

        a : row-major flat list, length m*n
        m : rows
        n : cols

        Returns a non-negative Python float.
        """
        if len(a) != m * n:
            raise ValueError(
                f"Matrix a requires {m * n} elements for shape ({m}, {n}), got {len(a)}"
            )

        arr_a = self._to_c_array(a)

        return float(
            self._lib.mat_frobenius_norm(
                self._ptr(arr_a),
                ctypes.c_int(m),
                ctypes.c_int(n),
            )
        )


# ------------------------------------------------------------------
# Standalone performance test (run this file directly to execute)
# ------------------------------------------------------------------

def _run_performance_test(iterations: int = 50_000_000) -> None:
    """
    Compare pure-Python vs C++ FFI speed for extreme_computation.
    Only executed when this module is run as __main__.
    """
    import math

    print(f"[Perf Test] {iterations:,} iterations")

    start_py = time.perf_counter()
    py_result = 0.0
    for i in range(iterations):
        py_result += math.pi * i / (i + 1.0)
    py_time = time.perf_counter() - start_py
    print(f"  Python  : {py_time:.4f}s  result={py_result:.6f}")

    bridge = CoreBridge()
    bridge.print_status()

    start_cpp = time.perf_counter()
    cpp_result = bridge.extreme_computation(iterations)
    cpp_time = time.perf_counter() - start_cpp
    print(f"  C++ FFI : {cpp_time:.4f}s  result={cpp_result:.6f}")

    if cpp_time > 0:
        print(f"  Speedup : {py_time / cpp_time:.1f}x")


if __name__ == "__main__":
    _run_performance_test()