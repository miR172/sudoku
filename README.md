sudoku
======

A GPU based sudoku solver--Genetic Algorithm based solver. 

compile with nvcc:

nvcc *.cu -o solver

run: file.in is the puzzle 9*9 number matrix without separations, one row per line in text
this will generate output: file.out

(UNSOLVED) One non-bug bug can't reach 162: the program is not going to stop!
However, with slightly lower score 160, the solution could be easily printed in 3 seconds.
(UNSOLVED) It seems that no solution could have 161 (? not testified), wonder whether something wrong with my evaluation().
If you knows why please let me know and if you are within my 5km range I could treat you beer for help.

Work cited/helped 
Sato, Y., Hasegawa, N., & Sato, M. (2011, June). GPU acceleration for Sudoku solution with genetic operations. In Evolutionary Computation (CEC), 2011 IEEE Congress on (pp. 296-303). IEEE.
Sato, Y., & Inoue, H. (2010, August). Solving Sudoku with genetic operations that preserve building blocks. In Computational Intelligence and Games (CIG), 2010 IEEE Symposium on (pp. 23-29). IEEE.
Mantere, T., & Koljonen, J. (2007, September). Solving, rating and generating Sudoku puzzles with GA. In Evolutionary Computation, 2007. CEC 2007. IEEE Congress on (pp. 1382-1389). IEEE.

-----------------
Obviously either I was made to do this or I was drunk...
