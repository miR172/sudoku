# ifndef SUDOKU
# define SUDOKU

//# define DEBUG(s) {printf(s); printf("\n");}
# define DEBUG(s)

# include <stdio.h>
# include <stdlib.h>

typedef enum __ENUM_puzzle_level{
  easy, medium, hard, hell
}puzzle_level;

typedef struct __STRUCT_location{
  int i;
  int j;
  int val;
  int on;
}loc;

typedef struct __STRUCT_sudoku_problem{
  int id;
  puzzle_level level;
  int ** map2chr; //pannel -> chr index, -1 if present
  int ** blk2chr; //block i -> chr start index, length
  int ** colpre; // val-1 in col present
  int ** rowpre; // val-1 in row present
  int ** solution;
  loc ** blocks; 
  int ** map; // missing number array, by block
  int chr_size; //size of one chromosome = length of all missing
}sudoku_puzzle;

void ini_location(loc *l, int i, int j, int val);

sudoku_puzzle* ini_puzzle(int id, FILE *f);

void export_sudoku(char * f, sudoku_puzzle *s, FILE *sf);

void clean_sudoku(sudoku_puzzle *s);

#endif
