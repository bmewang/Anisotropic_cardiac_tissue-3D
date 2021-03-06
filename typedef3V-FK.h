
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

#include "globalVariables.cuh"

typedef unsigned int uint;
typedef unsigned char uchar;
typedef unsigned char VolumeType;

#ifdef DOUBLE_PRECISION
	typedef double REAL;
#else
	typedef float REAL;
#endif

typedef struct stateVar {
	REAL *u, *v, *w;
} stateVar;

typedef struct conductionVar {
	REAL *x, *y, *z, *xy, *bx, *by;
} conductionVar;

typedef struct tableVar {
	REAL *m_w, *so, *si, *p_si, *wx;
} tableVar;

typedef struct electrodeVar {
	REAL e0, e1, e3;
} electrodeVar;

typedef struct paramVar {

	int memSize, totpoints;
	int count, countlim;
		// Physical parameters
	REAL Lx, Ly, Lz, hx, hy, hz, CFL_max, t, tlim;
	REAL dt;
	REAL diff_par, diff_per, diff_z;
	REAL Dxx, Dyy, Dzz;
	// Initial condition
	bool counterclock;   // Counterclock
	bool clock;  // Clock
	// Time and performance of simulation
	double fpsCount; // FPS count for averaging
	int frameCount;
	float physicalTime;
	float tiempo;
	int base;
	int prevFreme;
	int sampleRate;
	float3 singlePoint_cm;
	int singlePointPixel;
	float3 conductionBlockPoint;
	int conductionBlockPixel;
	char initDataName[100];

	#ifdef ANISOTROPIC_TISSUE
		REAL Dxy;
		REAL rotRate;
		REAL initTheta;
	  REAL d_theta;
	#else
		REAL rx, ry, rz;
	#endif

} paramVar;

typedef struct {
    REAL x, y, z; } vec3dyn;

typedef struct {
    REAL x, y, z, vx, vy, vz; } vec6dyn;
