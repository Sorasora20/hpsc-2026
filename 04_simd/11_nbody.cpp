#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <x86intrin.h>

int main() {
  const int N = 16;
  float x[N], y[N], m[N], fx[N], fy[N];
  for(int i=0; i<N; i++) {
    x[i] = drand48();
    y[i] = drand48();
    m[i] = drand48();
    fx[i] = fy[i] = 0;
  }
  __m512 xvec = _mm512_load_ps(x);
  __m512 yvec = _mm512_load_ps(y);
  __m512 mvec = _mm512_load_ps(m);
  __m512i jvec = _mm512_setr_epi32(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);

  for(int i=0; i<N; i++) {
    __mmask16 mask = _mm512_cmp_epi32_mask(_mm512_set1_epi32(i), jvec, _MM_CMPINT_NE);

    __m512 rxvec = _mm512_sub_ps(_mm512_set1_ps(x[i]), xvec);
    __m512 ryvec = _mm512_sub_ps(_mm512_set1_ps(y[i]), yvec);
    __m512 rx_2vec = _mm512_mul_ps(rxvec, rxvec);
    __m512 ry_2vec = _mm512_mul_ps(ryvec, ryvec);

    __m512 rvec = _mm512_rsqrt14_ps(_mm512_add_ps(rx_2vec, ry_2vec));
    __m512 r_3vec = _mm512_mul_ps(_mm512_mul_ps(rvec, rvec), rvec);

    __m512 dfxvec = _mm512_mul_ps(rxvec, _mm512_mul_ps(mvec, r_3vec));
    __m512 dfyvec = _mm512_mul_ps(ryvec, _mm512_mul_ps(mvec, r_3vec));

    __m512 zero = _mm512_setzero_ps();
    __m512 fxvec = _mm512_mask_blend_ps(mask, zero, _mm512_sub_ps(zero, dfxvec));
    __m512 fyvec = _mm512_mask_blend_ps(mask, zero, _mm512_sub_ps(zero, dfyvec));

    fx[i] = _mm512_reduce_add_ps(fxvec);
    fy[i] = _mm512_reduce_add_ps(fyvec);
    printf("%d %g %g\n",i,fx[i],fy[i]);
  }
}
