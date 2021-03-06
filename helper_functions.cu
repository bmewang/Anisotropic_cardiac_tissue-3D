
/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

Developed by: Hector Augusto Velasco-Perez 
@ CHAOS Lab 
@ Georgia Institute of Technology
August 07/10/2019

Special thanks to:
Dr. Flavio Fenton
Dr. Claire Yanyan Ji
Dr. Abouzar Kaboudian

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
*/

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "SOIL.h"

#include "typedef3V-FK.h"

__host__ __device__ int iDivUp(int a, int b) {
	return ((a % b) != 0) ? lrintf(a / b + 1) : (a / b);
}

void swapSoA(stateVar *A, stateVar *B) {
    stateVar temp = *A;
    *A = *B;
    *B = temp;
}

int initSinglePoint(float3 sp, paramVar param) {

	float ix = roundf(sp.x/param.hx + 1.f);
	float jy = roundf(sp.y/param.hy + 1.f);
	float kz = roundf(sp.z/param.hz + 1.f);

	int singlePoint = (int)(ix + nx*jy + nx*ny*kz);

	return singlePoint;
}

void screenShot(int w, int h) {
	
	time_t t = time(NULL);
	struct tm tm = *localtime(&t);

    char name[32];
    sprintf(name, "./DATA/figure_%d-%d-%d_%d-%d-%d.bmp", 
    	tm.tm_year + 1900, tm.tm_mon + 1, 
    	tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
      /* save a screenshot */
      // sudo apt-get install libsoil-dev
    SOIL_save_screenshot(name,
                         SOIL_SAVE_TYPE_BMP,
                         0, 0, w, h);

}

void chirality(int len_text, char text[], bool *counterclock, bool *clock) {

  // Default setup
  *counterclock = true;
  *clock = !counterclock;

  char c_to_search1[8] = "counter";
  char c_to_search2[7] = "clock";

  int pos_search = 0;
  int pos_text = 0;
  int len_search = 4;
  for (pos_text = 0; pos_text < len_text - len_search;++pos_text) {
      if(text[pos_text] == c_to_search1[pos_search]) {
          ++pos_search;
          if(pos_search == len_search) {
              // match
              *counterclock = true;
              *clock = false;
              //printf("match from %d to %d\n",pos_text-len_search,pos_text);
          }
      }
      else {
         pos_text -=pos_search;
         pos_search = 0;
      }
  }

  for (pos_text = 0; pos_text < len_text - len_search;++pos_text) {
      if(text[pos_text] == c_to_search2[pos_search]) {
          ++pos_search;
          if(pos_search == len_search) {
              // match
              *counterclock = false;
              *clock = true;
              //printf("match from %d to %d\n",pos_text-len_search,pos_text);
          }
      }
      else {
         pos_text -=pos_search;
         pos_search = 0;
      }

  }

}
