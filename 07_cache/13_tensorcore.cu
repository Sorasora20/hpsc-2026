#include <iostream>
#include <typeinfo>
#include <random>
#include <stdint.h>
#include <cublas_v2.h>
#include <mma.h>
#include <chrono>
using namespace std;
using namespace nvcuda;

__global__ void kernel(int dim_m, int dim_n, int dim_k,
                       const float *d_a, const float *d_b, float *d_c) {
  // H100向けにブロックタイルサイズを 128x128 に拡大
  int offset_m = blockIdx.x * 128;
  int offset_n = blockIdx.y * 128;

  // 1ブロックあたり 256スレッド (8ワープ) を使用
  int tid = threadIdx.x;
  int warp_id = tid / 32;

  // ダブルバッファリングとバンク競合回避のためのパディングを適用したShared Memory
  __shared__ half smem_a[2][32][136];
  __shared__ half smem_b[2][128][40];

  // ワープの配置 (4行 x 2列)
  int warp_row = warp_id % 4;
  int warp_col = warp_id / 4;

  // アキュムレータの初期化 (1ワープあたり 32x64 のタイルを処理 = 2x4 フラグメント)
  wmma::fragment<wmma::accumulator, 16, 16, 16, float> acc[2][4];
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 4; c++) {
      wmma::fill_fragment(acc[r][c], 0.0f);
    }
  }

  // グローバルメモリからShared Memoryへ float4 で読み込み half へ変換するラムダ関数
  auto load_Smem = [&](int k_idx, int buffer_idx) {
    // Aの読み込み (128x32)
    for (int i = tid; i < (128 * 32) / 4; i += 256) {
      int row = (i % 32) * 4;
      int col = i / 32;
      if (offset_m + row < dim_m && k_idx + col < dim_k) {
        float4 vec = *reinterpret_cast<const float4*>(&d_a[(k_idx + col) * dim_m + offset_m + row]);
        smem_a[buffer_idx][col][row + 0] = __float2half(vec.x);
        smem_a[buffer_idx][col][row + 1] = __float2half(vec.y);
        smem_a[buffer_idx][col][row + 2] = __float2half(vec.z);
        smem_a[buffer_idx][col][row + 3] = __float2half(vec.w);
      } else {
        smem_a[buffer_idx][col][row + 0] = __float2half(0.0f);
        smem_a[buffer_idx][col][row + 1] = __float2half(0.0f);
        smem_a[buffer_idx][col][row + 2] = __float2half(0.0f);
        smem_a[buffer_idx][col][row + 3] = __float2half(0.0f);
      }
    }
    // Bの読み込み (32x128)
    for (int i = tid; i < (32 * 128) / 4; i += 256) {
      int row = (i % 8) * 4;
      int col = i / 8;
      if (k_idx + row < dim_k && offset_n + col < dim_n) {
        float4 vec = *reinterpret_cast<const float4*>(&d_b[(offset_n + col) * dim_k + k_idx + row]);
        smem_b[buffer_idx][col][row + 0] = __float2half(vec.x);
        smem_b[buffer_idx][col][row + 1] = __float2half(vec.y);
        smem_b[buffer_idx][col][row + 2] = __float2half(vec.z);
        smem_b[buffer_idx][col][row + 3] = __float2half(vec.w);
      } else {
        smem_b[buffer_idx][col][row + 0] = __float2half(0.0f);
        smem_b[buffer_idx][col][row + 1] = __float2half(0.0f);
        smem_b[buffer_idx][col][row + 2] = __float2half(0.0f);
        smem_b[buffer_idx][col][row + 3] = __float2half(0.0f);
      }
    }
  };

  // ダブルバッファリングのための初期ロード
  int write_idx = 0;
  if (dim_k > 0) {
    load_Smem(0, write_idx);
  }
  __syncthreads();

  // メインループ
  for (int k = 0; k < dim_k; k += 32) {
    int read_idx = write_idx;
    write_idx ^= 1; // バッファの切り替え

    // 次のタイルのプリフェッチ（データロードのオーバーラップ）
    if (k + 32 < dim_k) {
      load_Smem(k + 32, write_idx);
    }

    // 計算フェーズ
    for (int step = 0; step < 2; step++) {
      wmma::fragment<wmma::matrix_a, 16, 16, 16, half, wmma::col_major> a_frag[2];
      wmma::fragment<wmma::matrix_b, 16, 16, 16, half, wmma::col_major> b_frag[4];

      // フラグメントをレジスタへ一括ロード (Smemアクセス数の削減)
      for (int r = 0; r < 2; r++) {
        wmma::load_matrix_sync(a_frag[r], &smem_a[read_idx][step * 16][warp_row * 32 + r * 16], 136);
      }
      for (int c = 0; c < 4; c++) {
        wmma::load_matrix_sync(b_frag[c], &smem_b[read_idx][warp_col * 64 + c * 16][step * 16], 40);
      }

      // 行列積和演算
      for (int r = 0; r < 2; r++) {
        for (int c = 0; c < 4; c++) {
          wmma::mma_sync(acc[r][c], a_frag[r], b_frag[c], acc[r][c]);
        }
      }
    }
    __syncthreads(); // 次のループに入る前の同期
  }

  // グローバルメモリへ結果の書き戻し
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 4; c++) {
      int c_m = offset_m + warp_row * 32 + r * 16;
      int c_n = offset_n + warp_col * 64 + c * 16;
      if (c_n < dim_n && c_m < dim_m) {
        wmma::store_matrix_sync(&d_c[c_n * dim_m + c_m], acc[r][c], dim_m, wmma::mem_col_major);
      }
    }
  }
}

int main(int argc, const char **argv) {
  int m = 10240;
  int k = 4096;
  int n = 8192;
  float alpha = 1.0;
  float beta = 0.0;
  int Nt = 10;

  float *A, *B, *C, *C2;
  cudaMallocManaged(&A, m * k * sizeof(float));
  cudaMallocManaged(&B, k * n * sizeof(float));
  cudaMallocManaged(&C, m * n * sizeof(float));
  cudaMallocManaged(&C2, m * n * sizeof(float));

  for (int i=0; i<m; i++)
    for (int j=0; j<k; j++)
      A[k*i+j] = drand48();
  for (int i=0; i<k; i++)
    for (int j=0; j<n; j++)
      B[n*i+j] = drand48();
  for (int i=0; i<n; i++)
    for (int j=0; j<m; j++)
      C[m*i+j] = C2[m*i+j] = 0;

  cublasHandle_t cublas_handle;
  cublasCreate(&cublas_handle);
  auto tic = chrono::steady_clock::now();
  for (int i = 0; i < Nt+2; i++) {
    if (i == 2) tic = chrono::steady_clock::now();
    cublasGemmEx(cublas_handle,
                 CUBLAS_OP_N,
                 CUBLAS_OP_N,
                 m, n, k,
                 &alpha,
                 A, CUDA_R_32F, m,
                 B, CUDA_R_32F, k,
                 &beta,
                 C, CUDA_R_32F, m,
                 CUBLAS_COMPUTE_32F_FAST_16F,
                 CUBLAS_GEMM_DEFAULT_TENSOR_OP);
    cudaDeviceSynchronize();
  }
  auto toc = chrono::steady_clock::now();
  int64_t num_flops = (2 * int64_t(m) * int64_t(n) * int64_t(k)) + (2 * int64_t(m) * int64_t(n));
  double tcublas = chrono::duration<double>(toc - tic).count() / Nt;
  double cublas_flops = double(num_flops) / tcublas / 1.0e9;

  // ---- 変更箇所：呼び出し側のタイリングとブロックサイズの修正 ----
  int tile_m = 128;
  int tile_n = 128;
  dim3 block = dim3(256); // スレッド数を64から256へ拡大
  dim3 grid = dim3((m + tile_m - 1) / tile_m, (n + tile_n - 1) / tile_n);

  for (int i = 0; i < Nt+2; i++) {
    if (i == 2) tic = chrono::steady_clock::now();
    kernel<<< grid, block >>>(m, n, k, A, B, C2);
    cudaDeviceSynchronize();
  }
  toc = chrono::steady_clock::now();
  double tcutlass = chrono::duration<double>(toc - tic).count() / Nt;
  double cutlass_flops = double(num_flops) / tcutlass / 1.0e9;

  printf("CUBLAS: %.2f Gflops, CUTLASS: %.2f Gflops\n", cublas_flops, cutlass_flops);

  double err = 0;
  for (int i=0; i<n; i++) {
    for (int j=0; j<m; j++) {
      err += fabs(C[m*i+j] - C2[m*i+j]);
    }
  }
  printf("error: %lf\n", err/n/m);

  cudaFree(A);
  cudaFree(B);
  cudaFree(C);
  cudaFree(C2);
  cublasDestroy(cublas_handle);
}
