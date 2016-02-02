#ifdef _OPENMP
#include <omp.h>
#endif

#include <iostream>
#include <limits>
#include <algorithm>
#include <new>
#include <cstring>

#include <CArena.H>
#include <PArray.H>
#include <MemPool.H>

namespace
{
  static PArray<CArena> the_memory_pool;
}

extern "C" {

void mempool_init()
{
#ifdef _OPENMP
  int nthreads = omp_get_max_threads();
#else
  int nthreads = 1;
#endif
  the_memory_pool.resize(nthreads, PArrayManage);
  for (int i=0; i<nthreads; ++i) {
    the_memory_pool.set(i, new CArena());
  }
#ifdef _OPENMP
#pragma omp parallel
#endif
  {
      size_t N = 1024*1024*sizeof(double);
      void *p = mempool_alloc(N);
      memset(p, 0, N);
      mempool_free(p);
  }
}

void* mempool_alloc (size_t nbytes)
{
#ifdef _OPENMP
  int tid = omp_get_thread_num();
#else
  int tid = 0;
#endif
  return the_memory_pool[tid].alloc(nbytes);
}

void mempool_free (void* p) 
{
#ifdef _OPENMP
  int tid = omp_get_thread_num();
#else
  int tid = 0;
#endif
  the_memory_pool[tid].free(p);
}

void mempool_get_stats (int& mp_min, int& mp_max, int& mp_tot) // min, max & tot in MB
{
  size_t hsu_min=std::numeric_limits<size_t>::max();
  size_t hsu_max=0;
  size_t hsu_tot=0;
  for (int i=0; i<the_memory_pool.size(); ++i) {
    size_t hsu = the_memory_pool[i].heap_space_used();
    hsu_min = std::min(hsu, hsu_min);
    hsu_max = std::max(hsu, hsu_max);
    hsu_tot += hsu;
  }
  mp_min = hsu_min/(1024*1024);
  mp_max = hsu_max/(1024*1024);
  mp_tot = hsu_tot/(1024*1024);
}

}
