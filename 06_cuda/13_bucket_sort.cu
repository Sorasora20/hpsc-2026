#include <cstdio>
#include <cstdlib>
#include <vector>

__global__ void initializeBucket(int* a) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  a[i] = 0;
}

__global__ void countKey(int *a, int *b) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  atomicAdd(&b[a[i]], 1);
}

__global__ void scan(int *a, int *b, int range) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  int val = (i > 0) ? a[i-1] : 0;
  __syncthreads();
  a[i] = val;
  __syncthreads();
  for(int j=1; j<range; j<<=1) {
    b[i] = a[i];
    __syncthreads();
    if(i>=j) a[i] += b[i-j];
    __syncthreads();
  }
}

__global__ void changeOrder(int *a, int *b, int *result) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  int val = a[idx];
  int i = atomicAdd(&b[val], 1);
  result[i] = val;
}

int main() {
  int n = 50;
  int range = 5;
  int *key;
  cudaMallocManaged(&key, n*sizeof(int));
  for (int i=0; i<n; i++) {
    key[i] = rand() % range;
    printf("%d ",key[i]);
  }
  printf("\n");

  int *bucket, *tmp, *result;
  cudaMallocManaged(&bucket, range*sizeof(int));
  cudaMallocManaged(&tmp, range*sizeof(int));
  cudaMallocManaged(&result, n*sizeof(int));

  initializeBucket<<<1, range>>>(bucket);
  countKey<<<1, n>>>(key, bucket);
  scan<<<1, range>>>(bucket, tmp, range);
  changeOrder<<<1, n>>>(key, bucket, result);
  cudaDeviceSynchronize();

  for (int i=0; i<n; i++) {
    printf("%d ",result[i]);
  }
  printf("\n");

  cudaFree(key);
  cudaFree(bucket);
  cudaFree(tmp);
  cudaFree(result);
}
