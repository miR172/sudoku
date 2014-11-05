# include <stdio.h>
# include <stdlib.h>
# include <string.h>
//# include <cuda.h>
# include <time.h>

# include "sudoku.h"

void ini_location(loc *l, int i, int j, int val){
  l->i = i;
  l->j = j;
  l->val = val;
  l->on = val==0?0:1;
}

sudoku_puzzle* ini_puzzle(int id, FILE *f){
  sudoku_puzzle *s = (sudoku_puzzle *)malloc(sizeof(sudoku_puzzle));
  s->id = id;

  s->map2chr = (int **)malloc(sizeof(int*)*9);
  s->colpre = (int **)malloc(sizeof(int*)*9);
  s->rowpre = (int **)malloc(sizeof(int*)*9);
  s->solution = (int **)malloc(sizeof(int*)*9);
  s->blocks = (loc **)malloc(sizeof(loc*)*9);

  int i;
  for(i=0; i<9; i++){
    s->map2chr[i] = (int *)malloc(sizeof(int)*9);
    s->solution[i] = (int *)malloc(sizeof(int)*9);
    s->colpre[i] = (int *)malloc(sizeof(int)*9);
    s->rowpre[i] = (int *)malloc(sizeof(int)*9);
    s->blocks[i] = (loc *)malloc(sizeof(loc)*9);

    int j = 0;
    for (;j<9;j++){ //initial
      s->colpre[i][j] = 0;
      s->rowpre[i][j] = 0;
      s->map2chr[i][j] = -1;
    }
  }

  DEBUG("start scan...");

  int j = 0;
  char buf;
  int tmp;
  while (j<9){
    i = 0;
    while (i<9){
      if (fscanf(f, "%c", &buf)){
        if (buf == '\n')
          continue;
        tmp = atoi(&buf);
        s->solution[j][i] = tmp;
        if (tmp != 0){
          s->colpre[i][tmp-1] = 1;
          s->rowpre[j][tmp-1] = 1;
        }
        //printf("puzzle[%d][%d], blocks[%d][%d] ", j, i, j/3*3+i/3, j%3*3+i%3);
        ini_location(&(s->blocks[j/3*3+i/3][j%3*3+i%3]), j, i, tmp);
        //printf("%d\n",s->blocks[j/3*3+i/3][j%3*3+i%3].on);
        i++;
      }
   }
    j++;
  }
  DEBUG("finish scan!");

  return s;
}


void export_sudoku(char * r, sudoku_puzzle *s, FILE *sf){
  
  DEBUG("start print...");
  int i, j;
  for(i=0;i<9;i++){
    for(j=0;j<9;j++){
      int x = s->map2chr[i][j];
      if (x!=-1){ s->solution[i][j] = r[x]-'0'; }
      fprintf(sf, "%d", s->solution[i][j]);
    }
  fprintf(sf, "\n");
  }
  DEBUG("finish export!");
}

void clean_sudoku(sudoku_puzzle *s){
  int i = 0;
  for(;i<9;i++){
    free(s->map2chr[i]);
    free(s->blk2chr[i]);
    free(s->colpre[i]);
    free(s->rowpre[i]);
    free(s->solution[i]);
    free(s->blocks[i]);
    free(s->map[i]);
  }
  free(s->map2chr);
  free(s->colpre);
  free(s->rowpre);
  free(s->solution);
  free(s->blocks);
  free(s->map);
  free(s->blk2chr);
  free(s);
}
