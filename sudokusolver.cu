# include <stdio.h>
# include <stdlib.h>
# include <time.h>
# include <cuda.h>
# include <curand_kernel.h>

# include "sudoku.h"

# define N 128//population size
# define BLKN 1 //grid size
# define M_RATE 0.5 //mutation rate
# define MUTATION 3 //schocastic mutation set size
# define TOURNAMENT 3 //schocastic tourament set size-1
# define MAX_CHR 74 //maximum chromosome size, 81 -(3^2-1) for unique solution
# define FULL 160 //maximum score 162 = 9*9*2

/*I can't get the program finished if this is 162 exactly. 
 *Reasoning that there can't be 161 score solution, 160 gives the right answer. 
 *Please help if you know why it doesn't terminate if this is 162
*/

# define CUDA_ERROR_CHECK(error) {\
           e = error; \
           if (e != cudaSuccess){ \
             DEBUG(cudaGetErrorString(e)); \
             free_exit(f, sf, pool, s); \
             return 0;\
           }	\
         }


// constant mem
static __constant__ int d_map2chr[9][9]; //position on pannel to chromosome index
static __constant__ int d_colpre[9][9]; //column present bits
static __constant__ int d_rowpre[9][9]; //row present bits, val-1 --> 1 or 0
static __constant__ int d_blk2chr[9][2]; //blk2chr[i] is [i_start, i_length] of i th block

void free_exit(FILE *f, FILE *sf, char * pool, sudoku_puzzle *s);

void shuffle(int * a, int n);

char * scan_puzzle(sudoku_puzzle *s, int pool_size);

__device__ int sum(int * a, int n){
  int i = 0;
  int r = 0;
  for (;i<n;i++){
    r += a[i];
  }
  return r;
}

__device__ void mutation(curandState *s, char * chrom){

  int i, x, y;
  float m;

  for (i=0;i<9;i++){//iterate on blocks
      m = curand_uniform(s); //decide whether to mutate
      if (m < M_RATE){ continue; }

      else{// chose 2 from the block_th block

        m = curand_uniform(s);
        x = (int)(m*d_blk2chr[i][1])%d_blk2chr[i][1]; // offset in block  ->1
        m = curand_uniform(s);
        y = (int)(m*d_blk2chr[i][1])%d_blk2chr[i][1]; // offset in block  ->2

        //swap
        char tmp = chrom[d_blk2chr[i][0]+x];
        chrom[d_blk2chr[i][0]+x] = chrom[d_blk2chr[i][0]+y];
        chrom[d_blk2chr[i][0]+y] = tmp;
      }
  }

  return;
}

__device__ void evaluate(int * allcs, int * allrs, char * chrom, int off){

  int cs = 0; //sum for 3 column: off*3-off*3+3
  int rs = 0; //sum for 3 row: off*3-off*3+3
  int i,j;

  for (i=0;i<3;i++){

    int x = off*3+i; //x_th
    int mc[9], mr[9];

    // cp from constant to local: present bits for x_th ROW and COL
    for (j=0;j<9;j++){
      mc[j] = d_colpre[x][j]; 
      mr[j] = d_rowpre[x][j];
    }

    for (j=0;j<9;j++){
      if (d_map2chr[x][j]!=-1){ // this element(x_th, j) on chromosome?
        mr[chrom[d_map2chr[x][j]]-'0'-1] = 1; } //yes -> change present bit ROW x has it now!
      if (d_map2chr[j][x]!=-1){ // this element(j, x_th) on chromosome? 
        mc[chrom[d_map2chr[j][x]]-'0'-1] = 1; } //yes -> change present bit COL x has it now!
    }

    cs += sum(mc, 9);
    rs += sum(mr, 9);
  }
  allcs[off] = cs;
  allrs[off] = rs;
}

__device__ void cpy2global(char * to, char * in, int n){
  int i;
  for(i=0;i<n;i++){
    to[i] = in[i];
  }
  return;
}

__global__ void ini_device(curandState * state, unsigned long seed){
  int id = threadIdx.x + blockIdx.x*blockDim.x;
  curand_init(seed, id, 0, &state[id]);
}

__global__ void solve(curandState * globalState, char * pp, char * final, int chr_size){

  __shared__ char chrs[N][MAX_CHR]; //population pool, >=rank^2 -1 given --> 1 solution 
  __shared__ char cross[N][MAX_CHR]; //child working area during crossing

  __shared__ int cscores[N][3]; // column scores
  __shared__ int rscores[N][3]; // row scores
  __shared__ int total[N]; // total scores

  __shared__ int pa[N]; // parents' id

  __shared__ int going; // flag


  // initialize, prepare, load to share mem
  int i,j;
  int chr = threadIdx.x;
 
  going = -1;

  for (i=0;i<chr_size;i++){ 
      chrs[chr][i] =  pp[chr*chr_size+i]; 
  }

  float rdf;
  int rdi;
  curandState localState = globalState[threadIdx.x + blockIdx.x*blockDim.x];
  
  __syncthreads();

  while (going < 0){

    // calculate scores
    for(i=0;i<3;i++){ evaluate(cscores[chr], rscores[chr], chrs[chr], i); }
    total[chr] = sum(rscores[chr], 3) + sum(cscores[chr], 3);

    if (total[chr] >= FULL){
      going = chr;
      cpy2global(final, chrs[chr], chr_size);
      return;
    }
   
    // tournament selection
    pa[chr] = chr;

    for (i=1;i<TOURNAMENT;i++){
      rdf = curand_uniform( &localState );
      rdi = (int)(rdf*N)%N;

      pa[chr] = total[rdi] > total[pa[chr]] ? rdi:pa[chr]; // thread id for chr_th parent
    }
    
    __syncthreads();

    // cross
    int win; //col/row winner id
    int p1 = pa[chr];
    int p2 = pa[N-1-chr];

    if (chr > N/2){ // perform ROW CROSS
      for (i=0;i<3;i++){
        win = rscores[p1][i] > rscores[p2][i] ? p1:p2;
        int k;
        for (k=0; k<3; k++){
          for (j=0; j<d_blk2chr[i*3+k][1];j++){ // off*3+{0,1,2} blocks in a row
            cross[chr][d_blk2chr[i*3+k][0]+j] = chrs[win][d_blk2chr[i*3+k][0]+j];
        }} // cpy from shared: generate child
      }
    }
    else { // perform COL CROSS
      for (i=0;i<3;i++){ 
        win = cscores[p1][i] > cscores[p2][i] ? p1:p2;
        int k;
        for (k=0; k<3; k++){
          for (j=0; j<d_blk2chr[i+k*3][1]; j++){ // off+{0,3,6} blocks in a column
            	//blk2chr[block]  = {start, length}
            cross[chr][d_blk2chr[i+k*3][0]+j] = chrs[win][d_blk2chr[i+k*3][0]+j]; 
        }}
      }
    }
    // evaluate
    for(i=0;i<3;i++){ evaluate(cscores[chr], rscores[chr], cross[chr], i); } // evaluate on working copy
    total[chr] = sum(rscores[chr], 3) + sum(cscores[chr], 3);
    if (total[chr] >= FULL){
      going = chr;
      cpy2global(final, cross[chr], chr_size);
      return;
    }
      // mutation
    for(i=0;i<MUTATION;i++){
      int max_score = total[chr];
      int tmp;
      mutation(&localState, cross[chr]); //mutate
      for(i=0;i<3;i++){ evaluate(cscores[chr], rscores[chr], cross[chr], i); } // evaluate on working copy
      tmp = sum(rscores[chr], 3) + sum(cscores[chr], 3);
      if (tmp>=FULL){
        going = chr;
        cpy2global(final, cross[chr], chr_size);
      }
      if (tmp > max_score){
        max_score = tmp;
        for (j=0;j<chr_size;j++){ chrs[chr][j] = cross[chr][j]; } // copy to pool
      }
    }
  }

  //globalState[threadIdx.x + blockIdx.x*blockDim.x] = localState;

}

//-------------------------------------

int main(int argc, char *argv[]){

  FILE *f, *sf;
  f = fopen(argv[1], "r");

  if (f==NULL){
    DEBUG("usage: sudokusolver filename.in");
    exit(0);
  }

  int fname_size = strlen(argv[1]);
  char fname_out[fname_size+1];
  char *temp = ".sol";
  memcpy(fname_out, argv[1], fname_size-3);
  memcpy(fname_out+fname_size-3, temp, 4);

  sf = fopen(fname_out, "w");
  if (sf==NULL){
    DEBUG("unable to create output file\n");
    exit(0);
  }

  sudoku_puzzle *s = ini_puzzle(0, f);
  char * pool = scan_puzzle(s, N);

  cudaError_t e;
  // constant
    // 1. generate continous 2D block local
  int blk2chr[9][2];
  int map2chr[9][9];
  int colpre[9][9];
  int rowpre[9][9];
  int i;

  for (i=0;i<9;i++){
    int j;
    blk2chr[i][0] = s->blk2chr[i][0];
    blk2chr[i][1] = s->blk2chr[i][1];
    for (j=0;j<9;j++){
      map2chr[i][j] = s->map2chr[i][j];
      colpre[i][j] = s->colpre[i][j];
      rowpre[i][j] = s->rowpre[i][j];
    }
  }

  CUDA_ERROR_CHECK(cudaMemcpyToSymbol(d_blk2chr, blk2chr, 9*2*sizeof(int)))

  CUDA_ERROR_CHECK(cudaMemcpyToSymbol(d_map2chr, map2chr, 9*9*sizeof(int)))

  CUDA_ERROR_CHECK(cudaMemcpyToSymbol(d_colpre, colpre, 9*9*sizeof(int)))

  CUDA_ERROR_CHECK(cudaMemcpyToSymbol(d_rowpre, rowpre, 9*9*sizeof(int)))

  DEBUG("\npannel_position(mapping)chromosome_index--constant\npresent bits by column & row--constant\n");

  // global mem  
  char * pp, * final;

  CUDA_ERROR_CHECK(cudaMalloc((void **)&pp, N*s->chr_size*sizeof(char)))
  CUDA_ERROR_CHECK(cudaMemcpy((void *)pp, pool, N*s->chr_size*sizeof(char), cudaMemcpyHostToDevice))
  //printf("allocated population %d*%d*%d = %d pool--global\n", N, s->chr_size, sizeof(char));

  CUDA_ERROR_CHECK(cudaMalloc((void **)&final, s->chr_size*sizeof(char)))
  DEBUG("allocated final char area--global\n");
  
  // init with random numbers, curand library
  curandState * allStates;
  cudaMalloc(&allStates, N*sizeof(curandState));
  ini_device<<<BLKN, N>>>(allStates, time(NULL));

  DEBUG("initialized--curand\nsolving....");

  solve<<<BLKN, N>>>(allStates, pp, final, s->chr_size);

  char * result = (char *)malloc(sizeof(char)*s->chr_size);
  CUDA_ERROR_CHECK(cudaMemcpy(result, final, s->chr_size*sizeof(char), cudaMemcpyDeviceToHost))
  //for (i=0;i<s->chr_size;i++){printf("%c", result[i]);}
  //printf("\n");
  DEBUG("\nsolved--GPU\n");

  export_sudoku(result, s, sf);
  
  // Free
  free(result);
  cudaFree(pp);
  cudaFree(final);
  cudaFree(allStates);
  
  free_exit(f, sf, pool, s);
  return 0;
}

void free_exit(FILE *f, FILE *sf, char * pool, sudoku_puzzle *s){
  fclose(f);
  fclose(sf);
  free(pool);
  clean_sudoku(s);
  exit(0);
}


void shuffle(int * array, int size){
  if (size>1){
    int i=0;
    for (; i<size-1; i++){
      int j = i + rand()/(RAND_MAX/(size-i) + 1);
      int t = array[j];
      array[j] = array[i];
      array[i] = t;
    }
  }
}

char * scan_puzzle(sudoku_puzzle *s, int pool_size){
  // scan and generate arrays
  int i, j;
  int ** map = (int **)malloc(sizeof(int *)*9);
  int ** map_chr = (int **)malloc(sizeof(int *)*9);
  int chr_size = 0;

  for (i=0; i<9; i++){
    // for each block

    int all[] = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    int n = 0; // missing in this blocks

    for (j=0; j<9; j++){
      if (s->blocks[i][j].on){ // present
        all[s->blocks[i][j].val-1] = 0; // set present to 0
      }else{ // missing
        int r = s->blocks[i][j].i;
        int c = s->blocks[i][j].j;
        s->map2chr[r][c] = chr_size + n;
        n++;
      }
    }

    map[i] = (int *)malloc(sizeof(int)*n); // missing
    map_chr[i] = (int *)malloc(sizeof(int)*2); //start, length
    map_chr[i][0] = i==0?0:map_chr[i-1][0] + map_chr[i-1][1];
    map_chr[i][1] = n; 
    chr_size += n;

    int k = 0;
    for (j=0; j<9; j++){
      if (all[j] != 0){ // non-0->missing
        map[i][k] = all[j];
        k++;
      }
    }
  }
                                                               
  // randomize initial chromosomes pool

  srand(time(NULL));
  int * pool = (int *)malloc(sizeof(int)*pool_size*chr_size);
  for (i=0; i<N; i++){ 
    for (j=0; j<9; j++){
      // printf("block %d size %d chrstart %d\n", j, map_chr[j][1], map_chr[j][0]);
      shuffle(map[j], map_chr[j][1]);
      memcpy(pool+i*chr_size+map_chr[j][0], map[j], map_chr[j][1]*sizeof(int));
    }
  }
  char * pc = (char *)malloc(sizeof(char)*pool_size*chr_size+1);
  char tmp[2];
  for (i=0;i<pool_size*chr_size;i++){
    sprintf(tmp, "%d", pool[i]);
    memcpy(&pc[i], tmp, sizeof(char));
  }

  s->map = map;
  s->blk2chr = map_chr;
  s->chr_size = chr_size;
  
  // debug
  /*
  for(i=0;i<pool_size;i++){
    printf("chromosome %d: ",i);
    for(j=0;j<chr_size;j++){
      printf("%d", pc[i*chr_size+j]-'0');
      //printf("%d",pool[i*chr_size+j]);
    }
    printf("\n");
  }
  */
  // debug
  free(pool);
  return pc;
}

