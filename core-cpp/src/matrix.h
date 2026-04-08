#ifndef MATRIX_H
#define MATRIX_H

#ifdef __cplusplus
extern "C"
{
#endif

    /*
     * mat_multiply
     *
     * Computes C = A * B using cache-tiled blocked multiplication.
     * Zero-copy: the caller allocates the output buffer.
     *
     * a   : row-major matrix of shape [m x k]
     * m   : rows of A
     * k   : shared dimension (cols of A, rows of B)
     * b   : row-major matrix of shape [k x n]
     * n   : cols of B
     * out : caller-allocated row-major output buffer of size [m x n]
     *       must not overlap with a or b
     */
    void mat_multiply(
        const double *a, int m, int k,
        const double *b, int n,
        double *out);

    /*
     * covariance_matrix
     *
     * Computes the sample covariance matrix from a returns matrix.
     * Zero-copy: the caller allocates the output buffer.
     *
     * returns  : row-major matrix of shape [assets x periods]
     *            each row is the time-series of returns for one asset
     * assets   : number of assets (rows)
     * periods  : number of return observations (cols)
     * out_cov  : caller-allocated row-major output buffer of size [assets x assets]
     */
    void covariance_matrix(
        const double *returns,
        int assets, int periods,
        double *out_cov);

    /*
     * mat_multiply_alloc
     *
     * Same computation as mat_multiply, but allocates the output buffer
     * internally using malloc.  The caller MUST release the returned pointer
     * with mat_free; never use free() or delete[] directly.
     *
     * Returns NULL if allocation fails or if any dimension is non-positive.
     */
    double *mat_multiply_alloc(
        const double *a, int m, int k,
        const double *b, int n);

    /*
     * mat_free
     *
     * Releases a buffer previously obtained from mat_multiply_alloc.
     * Calling with NULL is a no-op.
     */
    void mat_free(double *ptr);

    /*
     * cholesky_decompose
     *
     * Computes the lower-triangular Cholesky factor L such that A = L * L^T.
     * A must be a symmetric positive-definite matrix of shape [n x n], row-major.
     *
     * a      : input matrix [n x n], row-major; must be symmetric positive-definite
     * n      : dimension
     * l_out  : caller-allocated output buffer [n x n]; upper triangle is zeroed
     *
     * Returns 0 on success, -1 if A is not positive-definite or arguments are invalid.
     */
    int cholesky_decompose(
        const double *a, int n,
        double *l_out);

    /*
     * mat_vec_mul
     *
     * Computes y = A * x.
     * Zero-copy: the caller allocates the output buffer y.
     *
     * a : row-major matrix [m x n]
     * m : rows of A
     * n : cols of A (length of x)
     * x : input vector of length n
     * y : caller-allocated output vector of length m
     */
    void mat_vec_mul(
        const double *a, int m, int n,
        const double *x,
        double *y);

    /*
     * portfolio_variance
     *
     * Computes the scalar portfolio variance v = w^T * cov * w.
     *
     * cov     : row-major covariance matrix [assets x assets]
     * weights : portfolio weight vector of length assets
     * assets  : number of assets
     *
     * Returns the portfolio variance (a non-negative scalar).
     */
    double portfolio_variance(
        const double *cov,
        const double *weights,
        int assets);

    /*
     * mat_frobenius_norm
     *
     * Computes the Frobenius norm: sqrt( sum_{i,j} A[i,j]^2 ).
     *
     * a : row-major matrix [m x n]
     * m : rows
     * n : cols
     */
    double mat_frobenius_norm(
        const double *a, int m, int n);

#ifdef __cplusplus
}
#endif

#endif /* MATRIX_H */
