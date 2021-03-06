
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

__global__ void FK_3V_kernel(stateVar g_out, stateVar g_in, conductionVar r,
  REAL *J_d);
__host__ __device__ int iDivUp(int a, int b);

__global__ void singlePoint_kernel(stateVar g_in, REAL *pt_d,
   int singlePointPixel);
__global__ void copyRender_kernel(int totpoints, stateVar g_in, VolumeType *h_volume);
__global__ void spiralTip_kernel(REAL *g_past, stateVar g_present,
  VolumeType *h_vol);
__device__ bool filament(int s0, int sx, int sy, int sz, int sxy, int sxz, int syz, int sxyz,
  REAL *g_past, stateVar g_present);
__device__ double2 bilinearInterpolation(REAL x1, REAL x2, REAL x3, REAL x4,
                                         REAL y1, REAL y2, REAL y3, REAL y4);
__device__ int tip_push_back1(vec3dyn & mt);
__device__ int tip_push_back2(vec6dyn & mt);
