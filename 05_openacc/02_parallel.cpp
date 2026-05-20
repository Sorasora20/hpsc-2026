#include <cstdio>
#include <openacc.h>

int main() {
#pragma acc parallel
  {
#pragma acc loop
    for(int i=0; i<2; i++) {
      printf("%d: %d\n",__pgi_gangidx(),i);
    }
#pragma acc loop
    for(int i=0; i<2; i++) {
      printf("%d: %d\n",__pgi_gangidx(),i);
    }
  }
}
