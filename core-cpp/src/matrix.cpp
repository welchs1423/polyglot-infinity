#include "matrix.h"

#include <cstdlib>
#include <cstring>
#include <cmath>

/*
 * TILE_SIZE controls the blocking factor for the tiled matrix multiply.
 * 64 doubles = 512 bytes, which fits comfortably in L1 cache on most CPUs.
 */
static constexpr int TILE_SIZE = 64;

extern "C"
{

    /*
     * mat_multiply
     *
     * Cache-tiled (blocked) matrix multiplication: C = A * B
     *
     * Layout: row-major.  Element (i,j) of an [m x n] matrix M is M[i*n + j].
     *
     * Algorithm: iterate over (row-tile, col-tile, k-tile) triplets so that
     * the working set for each inner triple-loop fits in L1 cache, minimising
     * cache-miss penalties for large matrices.
     */
    void mat_multiply(
        const double *a, int m, int k,
        const double *b, int n,
        double *out)
    {
        if (!a || !b || !out || m <= 0 || k <= 0 || n <= 0)
        {
            return;
        }

        /* Zero the output buffer; the caller may pass uninitialised memory. */
        std::memset(out, 0, static_cast<std::size_t>(m) * n * sizeof(double));

        for (int ii = 0; ii < m; ii += TILE_SIZE)
        {
            const int i_end = (ii + TILE_SIZE < m) ? ii + TILE_SIZE : m;

            for (int ll = 0; ll < k; ll += TILE_SIZE)
            {
                const int l_end = (ll + TILE_SIZE < k) ? ll + TILE_SIZE : k;

                for (int jj = 0; jj < n; jj += TILE_SIZE)
                {
                    const int j_end = (jj + TILE_SIZE < n) ? jj + TILE_SIZE : n;

                    /* Inner kernel: accumulate tile product into out[ii..i_end, jj..j_end] */
                    for (int i = ii; i < i_end; ++i)
                    {
                        for (int l = ll; l < l_end; ++l)
                        {
                            const double a_il = a[i * k + l];
                            for (int j = jj; j < j_end; ++j)
                            {
                                out[i * n + j] += a_il * b[l * n + j];
                            }
                        }
                    }
                }
            }
        }
    }

    /*
     * covariance_matrix
     *
     * Computes the (unbiased) sample covariance matrix S where:
     *
     *   S[i][j] = sum_{t=0}^{T-1} (r_it - mu_i)(r_jt - mu_j) / (T - 1)
     *
     * The returns matrix is row-major with shape [assets x periods]:
     *   row i contains the T-length return series for asset i.
     */
    void covariance_matrix(
        const double *returns,
        int assets, int periods,
        double *out_cov)
    {
        if (!returns || !out_cov || assets <= 0 || periods < 2)
        {
            return;
        }

        const int T = periods;
        const double inv_T = 1.0 / static_cast<double>(T);
        const double inv_Tm1 = 1.0 / static_cast<double>(T - 1);

        /* Compute per-asset means. */
        double *means = static_cast<double *>(std::malloc(
            static_cast<std::size_t>(assets) * sizeof(double)));
        if (!means)
        {
            return;
        }

        for (int i = 0; i < assets; ++i)
        {
            double sum = 0.0;
            const double *row = returns + i * T;
            for (int t = 0; t < T; ++t)
            {
                sum += row[t];
            }
            means[i] = sum * inv_T;
        }

        /* Compute upper triangle of the covariance matrix, then mirror. */
        std::memset(out_cov, 0, static_cast<std::size_t>(assets) * assets * sizeof(double));

        for (int i = 0; i < assets; ++i)
        {
            const double *ri = returns + i * T;
            for (int j = i; j < assets; ++j)
            {
                const double *rj = returns + j * T;
                double cov = 0.0;
                for (int t = 0; t < T; ++t)
                {
                    cov += (ri[t] - means[i]) * (rj[t] - means[j]);
                }
                cov *= inv_Tm1;
                out_cov[i * assets + j] = cov;
                out_cov[j * assets + i] = cov;
            }
        }

        std::free(means);
    }

    /*
     * mat_multiply_alloc
     *
     * Allocates the result buffer internally; the caller must call mat_free.
     */
    double *mat_multiply_alloc(
        const double *a, int m, int k,
        const double *b, int n)
    {
        if (!a || !b || m <= 0 || k <= 0 || n <= 0)
        {
            return nullptr;
        }

        const std::size_t sz = static_cast<std::size_t>(m) * n;
        double *out = static_cast<double *>(std::malloc(sz * sizeof(double)));
        if (!out)
        {
            return nullptr;
        }

        mat_multiply(a, m, k, b, n, out);
        return out;
    }

    /*
     * mat_free
     *
     * Counterpart to mat_multiply_alloc.  Uses the same allocator (malloc/free)
     * so the deallocation path is unambiguous across C/C++ boundary.
     */
    void mat_free(double *ptr)
    {
        std::free(ptr);
    }

    /*
     * cholesky_decompose
     *
     * Computes the lower-triangular Cholesky factor L such that A = L * L^T
     * using the standard Cholesky-Banachiewicz algorithm (O(n^3/3)).
     *
     * The upper triangle of l_out is zeroed; only the lower triangle is filled.
     * A must be symmetric positive-definite.
     *
     * Returns 0 on success, -1 if A is not positive-definite or inputs are invalid.
     */
    int cholesky_decompose(const double *a, int n, double *l_out)
    {
        if (!a || !l_out || n <= 0)
        {
            return -1;
        }

        std::memset(l_out, 0, static_cast<std::size_t>(n) * n * sizeof(double));

        for (int i = 0; i < n; ++i)
        {
            for (int j = 0; j <= i; ++j)
            {
                double sum = 0.0;
                for (int t = 0; t < j; ++t)
                {
                    sum += l_out[i * n + t] * l_out[j * n + t];
                }
                if (i == j)
                {
                    const double d = a[i * n + i] - sum;
                    if (d <= 0.0)
                    {
                        /* A is not positive-definite; zero l_out to prevent partial use. */
                        std::memset(l_out, 0, static_cast<std::size_t>(n) * n * sizeof(double));
                        return -1;
                    }
                    l_out[i * n + j] = std::sqrt(d);
                }
                else
                {
                    if (l_out[j * n + j] == 0.0)
                    {
                        std::memset(l_out, 0, static_cast<std::size_t>(n) * n * sizeof(double));
                        return -1;
                    }
                    l_out[i * n + j] = (a[i * n + j] - sum) / l_out[j * n + j];
                }
            }
        }
        return 0;
    }

    /*
     * mat_vec_mul
     *
     * Computes y = A * x using a simple row-dot-product loop.
     * Zero-copy: y points into caller-owned memory.
     */
    void mat_vec_mul(
        const double *a, int m, int n,
        const double *x,
        double *y)
    {
        if (!a || !x || !y || m <= 0 || n <= 0)
        {
            return;
        }

        for (int i = 0; i < m; ++i)
        {
            double acc = 0.0;
            const double *row = a + i * n;
            for (int j = 0; j < n; ++j)
            {
                acc += row[j] * x[j];
            }
            y[i] = acc;
        }
    }

    /*
     * portfolio_variance
     *
     * Computes v = w^T * cov * w via two passes:
     *   1. tmp = cov * w   (mat_vec_mul, O(assets^2))
     *   2. v   = w^T * tmp (dot product, O(assets))
     *
     * An internal tmp buffer is allocated and freed within this function.
     * No allocation escapes the function boundary.
     */
    double portfolio_variance(
        const double *cov,
        const double *weights,
        int assets)
    {
        if (!cov || !weights || assets <= 0)
        {
            return 0.0;
        }

        double *tmp = static_cast<double *>(
            std::malloc(static_cast<std::size_t>(assets) * sizeof(double)));
        if (!tmp)
        {
            return 0.0;
        }

        mat_vec_mul(cov, assets, assets, weights, tmp);

        double result = 0.0;
        for (int i = 0; i < assets; ++i)
        {
            result += weights[i] * tmp[i];
        }

        std::free(tmp);
        return result;
    }

    /*
     * mat_frobenius_norm
     *
     * Computes sqrt( sum_{i,j} a[i,j]^2 ) in a single pass.
     * No allocation; reads only from the caller-supplied buffer.
     */
    double mat_frobenius_norm(const double *a, int m, int n)
    {
        if (!a || m <= 0 || n <= 0)
        {
            return 0.0;
        }

        double sum = 0.0;
        const int total = m * n;
        for (int i = 0; i < total; ++i)
        {
            sum += a[i] * a[i];
        }
        return std::sqrt(sum);
    }

} /* extern "C" */
