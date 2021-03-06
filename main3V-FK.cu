
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
#include <string.h>
#include <vector>

// CUDA Runtime, Interop, and includes
#include <cuda_runtime.h>
#include <cuda_profiler_api.h>
#include <vector_types.h>

// OpenGL libraries
#include <GL/glew.h>
#include <GL/glut.h>
#include <GL/freeglut.h>
#include <cuda_runtime_api.h>
#include <cuda_gl_interop.h>
#include "openGLPrototypes.h"

#include "typedef3V-FK.h"
//#include "globalVariables.cuh"

// Performance libraries
#include "./common/CudaSafeCall.h"
#include "./common/profile_time.h"

// Function protoypes
#include "hostPrototypes.h"
#include "devicePrototypes.cuh"

/*------------------------------------------------------------------------
* Declare global variables
*------------------------------------------------------------------------
*/

// Decladre structudre for most of the parameters
paramVar param;

// Weight coefficients for finite differences
REAL rxyc, rxzc, ryzc;
REAL rCxyz, rwe, rsn, rbt, rxyzf;

// Miscellaneous constants
REAL expTau_vp, expTau_wp, expTau_wn;
REAL invdx, invdy, invdz;

// Isotropic constants
__constant__ REAL dt_d, rx_d, ry_d, rz_d;
__constant__ REAL rCxyz_d, rwe_d, rsn_d, rbt_d;
__constant__ REAL rxyc_d, rxzc_d, ryzc_d, rxyzf_d;
__constant__ REAL rxy_d, rbx_d, rby_d;

// Miscellaneous constants
__constant__ REAL expTau_vp_d, expTau_wp_d, expTau_wn_d;
__constant__ REAL invdx_d, invdy_d, invdz_d;

dim3 grid3D, grid3Dz, grid1D;
dim3 block3D, block3Dz, block1D;

// Voltage and gate arrays
stateVar gate_h, gateIn_d, gateOut_d;

// Conduction arrays
conductionVar r, r_d;

// Array for currents
REAL *J_current_d, *v_past_d;

/*------------------------------------------------------------------------
* Miscellaneous
*------------------------------------------------------------------------
*/

//Array for the tip trajectory
int tipTraFlag = 1;

// Single point
REAL *point_h, *point_d, *point_h2;
std::vector<electrodeVar> electrode;

// Arrays for the tip trajectory
__device__ vec3dyn dev_data1[NN];
__device__ vec6dyn dev_data2[NN];
__device__ int dev_count = 0;
std::vector<int> dsizeTip;

// Initial condition parameters
bool initConditionFlag = true;

// toggle
bool animate = true;

// Output directory (pwd)
char strAdress[] = "./DATA/EPIENDO1/";
//char strAdress[] = "../../../../../../../media/sopst/DATA/ResponceFunctions/DATA/EPIENDO1";
int sbytes = strlen(strAdress);

/*------------------------------------------------------------------------
* 3D volume renderer
*------------------------------------------------------------------------
*/

size_t size;

cudaExtent volumeSize = make_cudaExtent(nx, ny, nz);

// Simple struct which contains the position and color of a vertex
struct SVertex
{
    GLfloat x,y,z;
    GLfloat r,g,b;
};

// Data for the vertices
SVertex *g_pVertices = NULL;
int  g_nVertices;            // Size of the vertex array
int  g_nVerticesPopulated;   // Number currently populated

uint width_3d = 1024, height_3d = 1024;
dim3 blockSize(16, 16);
dim3 gridSize;

float3 viewRotation;
float3 viewTranslation = make_float3(0.0, 0.0, -4.0f);
float invViewMatrix[12];

float density = 0.13f;//0.05f;
float brightness = 1.20f;
float transferOffset = 0.0f;
float transferScale = 1.0f;
bool linearFiltering = true;

GLuint pbo = 0;     // OpenGL pixel buffer object
GLuint tex = 0;     // OpenGL texture object
// CUDA Graphics Resource (to transfer PBO)
struct cudaGraphicsResource *cuda_pbo_resource;

static double starttime = 0;
static bool first = true;
static int frames = 0;

int ox, oy;
int buttonState = 0;

VolumeType *h_volume;

/*------------------------------------------------------------------------
* Program starts here
*-------------------------------------------------------------------------
*/

int main(int argc, char **argv) {

// Memory size declaration (for host and device)
param.memSize = nx*ny*nz*sizeof(REAL);
// memory size declaration (3d volume renderer)
size = volumeSize.width*volumeSize.height*volumeSize.depth*sizeof(VolumeType);

param.totpoints = nx*ny*nz;

param.CFL_max = 0.4; // Courant stability condition

// Physical length (cm)
param.Lx = 10.0f;
param.Ly = 10.0f;
param.Lz = 0.3;
// Physical spacing between nodes (cm)
param.hx = param.Lx/(nx);
param.hy = param.Ly/(ny);
param.hz = param.Lz/(nz);
//param.dt = (1.0/diff)*(CFL_max-0.1)*(hx*hx*hy*hy)/(hx*hx+hy*hy);

// Time
param.dt = 0.01f;
param.t = 0.0f;
param.tlim = 1000.0f;
param.sampleRate = 200;

// Global counter
param.count = 0;
param.countlim = 1000;

// Frame tracking
param.fpsCount = 0.0;  // FPS count for averaging
param.frameCount = 0;
param.physicalTime = 0.0f;

// Position in 3D to measure voltage in time (electrode)
param.singlePoint_cm = make_float3(0.05*param.Lx, 0.05*param.Ly, 0.1*param.Lz);
param.conductionBlockPoint = make_float3(param.Lx/2,param.Ly/2,param.Lz/2);

#ifdef ANISOTROPIC_TISSUE
  param.rotRate = 60.f; // deg/mm
  param.diff_par = 0.001f;
  param.diff_per = 0.0002f;
  param.diff_z = 0.0002f;
  param.d_theta = param.Lz*10.f*param.rotRate;
  param.initTheta = param.d_theta/2;

#else

  param.diff_par = 0.001f;
  param.diff_per = 0.001f;
  param.diff_z = param.diff_per;
#endif

#ifdef LOAD_DATA
  char pwdAdress[] = "./initial_conditions/readyCUDA/init_g2.4.dat";
  strcpy(param.initDataName, pwdAdress);
#else
  strcpy(param.initDataName, "User input conduction block");
#endif

// Rotation direction (chirality)
chirality(200,pwdAdress,&param.counterclock,&param.clock);

/*------------------------------------------------------------------------
* Output for terminal
*------------------------------------------------------------------------
*/

printf("String size %d\n", sbytes);
printf("\n********Grid dimensions*********\n");
printf("# of grid points X = %d\n", nx);
printf("# of grid points Y = %d\n", ny);
printf("# of grid points Z = %d\n", nz);
printf("Total number of nodes: %d\n", param.totpoints);

printf("\n********Spatial dimensions*********\n");
printf("Physical dx %f cm \n", param.hx);
printf("Physical dy %f cm \n", param.hy);
printf("Physical dz %f cm \n", param.hz);
printf("Physical Lx length %f cm \n", param.Lx);
printf("Physical Ly length %f cm \n", param.Ly);
printf("Physical Lz length %f cm \n", param.Lz);

printf("\n********Time*********\n");
printf("Time step: %f ms\n", param.dt);

/*------------------------------------------------------------------------
* Array allocation
*------------------------------------------------------------------------
*/

// Array allocation
gate_h.u = (REAL*)malloc(param.memSize);
gate_h.v = (REAL*)malloc(param.memSize);
gate_h.w = (REAL*)malloc(param.memSize);

// For variables in time
point_h = (REAL*)malloc(3*sizeof(REAL));

// Conduction  block
point_h2 = (REAL*)malloc(sizeof(REAL));
point_h2[0] = 0.f;

//Push back new subject created with default constructor.
dsizeTip.push_back(int());

// Allocate device memory arrays
CudaSafeCall(cudaMalloc((void **) &gateIn_d.u, param.memSize));
CudaSafeCall(cudaMalloc((void **) &gateIn_d.v, param.memSize));
CudaSafeCall(cudaMalloc((void **) &gateIn_d.w, param.memSize));

CudaSafeCall(cudaMalloc((void **) &gateOut_d.u, param.memSize));
CudaSafeCall(cudaMalloc((void **) &gateOut_d.v, param.memSize));
CudaSafeCall(cudaMalloc((void **) &gateOut_d.w, param.memSize));

CudaSafeCall(cudaMalloc((void **) &J_current_d, param.memSize));
CudaSafeCall(cudaMalloc((void **) &v_past_d, param.memSize));

// Variables in time
CudaSafeCall(cudaMalloc((void **) &point_d, 2*sizeof(REAL)));

CudaSafeCall(cudaMemcpyToSymbol(dt_d, &param.dt, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

CudaSafeCall(cudaMalloc((void**)&h_volume, size));

puts("Finished allocating device arrays\n");

/*------------------------------------------------------------------------
* Initializing physical arrays. Copy from host to device
*------------------------------------------------------------------------
*/

// Initiate arrays
initGates(gate_h,gateOut_d,gateIn_d,param.memSize,J_current_d);

// Convert cm to pixels for electrode measurement
param.singlePointPixel = initSinglePoint(param.singlePoint_cm, param);

/*------------------------------------------------------------------------
* Anysotropic parameters
*------------------------------------------------------------------------
*/

#ifdef ANISOTROPIC_TISSUE

int k;

REAL degrad, theta;

r.x = (REAL*)malloc(nz*sizeof(REAL));
r.y = (REAL*)malloc(nz*sizeof(REAL));
r.z = (REAL*)malloc(nz*sizeof(REAL));
r.xy = (REAL*)malloc(nz*sizeof(REAL));
r.bx = (REAL*)malloc(nz*sizeof(REAL));
r.by = (REAL*)malloc(nz*sizeof(REAL));

CudaSafeCall(cudaMalloc((void **) &r_d.x, nz*sizeof(REAL)));
CudaSafeCall(cudaMalloc((void **) &r_d.y, nz*sizeof(REAL)));
CudaSafeCall(cudaMalloc((void **) &r_d.z, nz*sizeof(REAL)));
CudaSafeCall(cudaMalloc((void **) &r_d.xy, nz*sizeof(REAL)));
CudaSafeCall(cudaMalloc((void **) &r_d.bx, nz*sizeof(REAL)));
CudaSafeCall(cudaMalloc((void **) &r_d.by, nz*sizeof(REAL)));

#ifdef DOUBLE_PRECISION

printf("DOUBLE PRECISION setup\n");

rCxyz = -4.0/3.0;
rwe = 1.0/6.0;
rsn = 1.0/6.0;
rbt = 1.0/6.0;
rxyc = 1.0/12.0;
rxzc = 1.0/12.0;
ryzc = 1.0/12.0;
rxyzf = 1.0/12.0;

for (k=0;k<nz;k++) {


    #ifdef PERIODIC_Z
      degrad = param.d_theta*k/(nz) - param.initTheta;
      //puts("PERIODIC Z BOUNDARY CONDITIONS\n");
    #else
      degrad = param.d_theta*k/(nz-1) - param.initTheta;
      //puts("ZERO-FLUX Z BOUNDARY CONDITIONS");
    #endif

    theta = degrad*pi/180.0;
    param.Dxx = param.diff_par*cos(theta)*cos(theta) +
      param.diff_per*sin(theta)*sin(theta);
    param.Dyy = param.diff_par*sin(theta)*sin(theta) +
      param.diff_per*cos(theta)*cos(theta);
    param.Dzz = param.diff_z;
    param.Dxy = (param.diff_par - param.diff_per)*sin(theta)*cos(theta);

    printf("Angle %d %f\n", k, degrad);

    r.x[k]  = param.Dxx*param.dt/(param.hx*param.hx);
    r.y[k]  = param.Dyy*param.dt/(param.hy*param.hy);
    r.z[k]  = param.Dzz*param.dt/(param.hz*param.hz); // <- Notice this is a constant
    r.xy[k] = 2.0*param.Dxy*param.dt/(4.0*param.hx*param.hy);
    r.bx[k] = param.hx*param.Dxy/(param.Dxx*param.hy);
    r.by[k] = param.hy*param.Dxy/(param.Dyy*param.hx);

    if ( ( r.x[k] + r.y[k] + r.z[k] ) > param.CFL_max ) {
      printf("Numerical instability risk (Anisotropic) \n");
      printf("rx = %f, ry = %f, rz = %f, rxy = %f\n", r.x[k], r.y[k],
        r.z[k], r.xy[k]);
      printf("\n Abort \n");
      exitProgram();

    }

  }

/*------------------------------------------------------------------------
* Miscellaneous constants declaration
*-------------------------------------------------------------------------
*/

expTau_vp = exp(-param.dt/tau_vp);
expTau_wp = exp(-param.dt/tau_wp);
expTau_wn = exp(-param.dt/tau_wn);

invdx = 0.5/param.hx;
invdy = 0.5/param.hy;
invdz = 0.5/param.hz;

#else

printf("SINGLE PRECISION setup\n");

rCxyz = -4.f/3.f;
rwe = 1.f/6.f;
rsn = 1.f/6.f;
rbt = 1.f/6.f;
rxyc = 1.f/12.f;
rxzc = 1.f/12.f;
ryzc = 1.f/12.f;
rxyzf = 1.f/12.f;

for (k=0;k<nz;k++) {

    #ifdef PERIODIC_Z
      degrad = param.d_theta*k/(nz) - param.initTheta;
      //puts("PERIODIC Z BOUNDARY CONDITIONS\n");
    #else
      degrad = param.d_theta*k/(nz-1) - param.initTheta;
      //puts("ZERO-FLUX Z BOUNDARY CONDITIONS");
    #endif

    theta = degrad*pi/180.0f;
    param.Dxx = param.diff_par*cosf(theta)*cosf(theta) +
      param.diff_per*sinf(theta)*sinf(theta);
    param.Dyy = param.diff_par*sinf(theta)*sinf(theta) +
      param.diff_per*cosf(theta)*cosf(theta);
    param.Dzz = param.diff_z;
    param.Dxy = (param.diff_par - param.diff_per)*sinf(theta)*cosf(theta);

    printf("Angle %d %f\n", k, degrad);

    r.x[k]  = param.Dxx*param.dt/(param.hx*param.hx);
    r.y[k]  = param.Dyy*param.dt/(param.hy*param.hy);
    r.z[k]  = param.Dzz*param.dt/(param.hz*param.hz); // <- Notice this is a constant
    r.xy[k] = 2.f*param.Dxy*param.dt/(4.f*param.hx*param.hy);
    r.bx[k] = param.hx*param.Dxy/(param.Dxx*param.hy);
    r.by[k] = param.hy*param.Dxy/(param.Dyy*param.hx);

    if ( ( r.x[k] + r.y[k] + r.z[k] ) > param.CFL_max ) {
      printf("Numerical instability risk (Anisotropic) \n");
      printf("rx = %f, ry = %f, rz = %f, rxy = %f\n", r.x[k], r.y[k],
        r.z[k], r.xy[k]);
      printf("\n Abort \n");
      exitProgram();

    }

  }

  /*------------------------------------------------------------------------
  * Miscellaneous constants declaration
  *------------------------------------------------------------------------
  */

  expTau_vp = expf(-param.dt/tau_vp);
  expTau_wp = expf(-param.dt/tau_wp);
  expTau_wn = expf(-param.dt/tau_wn);

  invdx = 0.5f/param.hx;
  invdy = 0.5f/param.hy;
  invdz = 0.5f/param.hz;

#endif

/*------------------------------------------------------------------------
* Miscellaneous constants allocation
*------------------------------------------------------------------------
*/

CudaSafeCall(cudaMemcpyToSymbol(rCxyz_d, &rCxyz, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rwe_d, &rwe, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rsn_d, &rsn, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rbt_d, &rbt, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rxyc_d, &rxyc, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rxzc_d, &rxzc, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(ryzc_d, &ryzc, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rxyzf_d, &rxyzf, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

CudaSafeCall(cudaMemcpyToSymbol(expTau_vp_d, &expTau_vp, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(expTau_wp_d, &expTau_wp, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(expTau_wn_d, &expTau_wn, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

CudaSafeCall(cudaMemcpyToSymbol(invdx_d, &invdx, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(invdy_d, &invdy, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(invdz_d, &invdz, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

CudaSafeCall(cudaMemcpy(r_d.x, r.x, nz*sizeof(REAL), cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpy(r_d.y, r.y, nz*sizeof(REAL), cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpy(r_d.z, r.z, nz*sizeof(REAL), cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpy(r_d.xy, r.xy, nz*sizeof(REAL), cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpy(r_d.bx, r.bx, nz*sizeof(REAL), cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpy(r_d.by, r.by, nz*sizeof(REAL), cudaMemcpyHostToDevice));

printf("ANISOTROPIC TISSUE allocation finished\n");

#else

/*------------------------------------------------------------------------
* Isotropic parameters
*------------------------------------------------------------------------
*/

param.Dxx = param.diff_par;
param.Dyy = param.diff_per;
param.Dzz = param.diff_z;

#ifdef DOUBLE_PRECISION

printf("DOUBLE PRECISION setup\n");

param.rx = param.dt*param.Dxx/(param.hx*param.hx);
param.ry = param.dt*param.Dyy/(param.hy*param.hy);
param.rz = param.dt*param.Dzz/(param.hz*param.hz);

rCxyz = -4.0/3.0 * (param.rx + param.ry + param.rz);
rwe = 2.0/3.0 * param.rx - param.ry/6.0 - param.rz/6.0;
rsn = 2.0/3.0 * param.ry - param.rx/6.0 - param.rz/6.0;
rbt = 2.0/3.0 * param.rz - param.ry/6.0 - param.rx/6.0;
rxyc = 1.0/12.0 * (param.rx + param.ry);
rxzc = 1.0/12.0 * (param.rx + param.rz);
ryzc = 1.0/12.0 * (param.ry + param.rz);
rxyzf = 1.0/12.0;

/*------------------------------------------------------------------------
* Miscellaneous constants declaration
*------------------------------------------------------------------------
*/

expTau_vp = exp(-param.dt/tau_vp);
expTau_wp = exp(-param.dt/tau_wp);
expTau_wn = exp(-param.dt/tau_wn);

invdx = 0.5/param.hx;
invdy = 0.5/param.hy;
invdz = 0.5/param.hz;

#else

printf("SINGLE PRECISION setup\n");

param.rx = param.dt*param.Dxx/(param.hx*param.hx);
param.ry = param.dt*param.Dyy/(param.hy*param.hy);
param.rz = param.dt*param.Dzz/(param.hz*param.hz);

rCxyz = -4.f/3.f * (param.rx + param.ry + param.rz);
rwe = 2.f/3.f * param.rx - param.ry/6.f - param.rz/6.f;
rsn = 2.f/3.f * param.ry - param.rx/6.f - param.rz/6.f;
rbt = 2.f/3.f * param.rz - param.ry/6.f - param.rx/6.f;
rxyc = 1.f/12.f*(param.rx + param.ry);
rxzc = 1.f/12.f*(param.rx + param.rz);
ryzc = 1.f/12.f*(param.ry + param.rz);
rxyzf = 1.f/12.f;

/*------------------------------------------------------------------------
* Miscellaneous constants declaration
*------------------------------------------------------------------------
*/

expTau_vp = expf(-param.dt/tau_vp);
expTau_wp = expf(-param.dt/tau_wp);
expTau_wn = expf(-param.dt/tau_wn);

invdx = 0.5f/param.hx;
invdy = 0.5f/param.hy;
invdz = 0.5f/param.hz;

#endif

if ( ( param.rx + param.ry + param.rz ) > param.CFL_max ) {
  printf("Numerical instability risk (Isotropic) \n");
  printf("rx = %f, ry = %f, rz = %f\n", param.rx, param.ry, param.rz);
  printf("\n Abort \n");
  exitProgram();

}

CudaSafeCall(cudaMemcpyToSymbol(rx_d, &param.rx, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(ry_d, &param.ry, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rz_d, &param.rz, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

CudaSafeCall(cudaMemcpyToSymbol(rCxyz_d, &rCxyz, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rwe_d, &rwe, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rsn_d, &rsn, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rbt_d, &rbt, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rxyc_d, &rxyc, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rxzc_d, &rxzc, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(ryzc_d, &ryzc, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(rxyzf_d, &rxyzf, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

/*------------------------------------------------------------------------
* Miscellaneous constants allocation
*------------------------------------------------------------------------
*/

CudaSafeCall(cudaMemcpyToSymbol(expTau_vp_d, &expTau_vp, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(expTau_wp_d, &expTau_wp, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(expTau_wn_d, &expTau_wn, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

CudaSafeCall(cudaMemcpyToSymbol(invdx_d, &invdx, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(invdy_d, &invdy, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));
CudaSafeCall(cudaMemcpyToSymbol(invdz_d, &invdz, sizeof(REAL), 0,
  cudaMemcpyHostToDevice));

printf("rx = %f \n", param.rx);
printf("ry = %f \n", param.ry);
printf("rz = %f \n", param.rz);

printf("\n********Diffusion*********\n");
printf("Diffusion x component: %f cm^2/ms\n", param.Dxx);
printf("Diffusion y component: %f cm^2/ms\n", param.Dyy);
printf("Diffusion z component: %f cm^2/ms\n", param.Dzz);

printf("ISOTROPIC MEDIA allocation finished\n");

#endif

/*------------------------------------------------------------------------
* OpenGL setup
*------------------------------------------------------------------------
*/

// 3D rendering preparatives
if (false == initGL(&argc, argv)) exit(0);
gridSize = dim3(iDivUp(width_3d, blockSize.x), iDivUp(height_3d, blockSize.y));

puts("Finished initalizing variables\n");

/*------------------------------------------------------------------------
* Kernels setup
*------------------------------------------------------------------------
*/

grid3D = dim3(ny, nz, 1);
block3D = dim3(nx, 1, 1);

grid3Dz = dim3(nx, ny, 1);
block3Dz = dim3(1, nz, 1);

int numSMs;
cudaDeviceGetAttribute(&numSMs, cudaDevAttrMultiProcessorCount, 0);

grid1D = dim3(32*numSMs, 1, 1);
block1D = dim3(BLOCK_LENGTH, 1, 1);

puts("Starting simulation\n");

/*------------------------------------------------------------------------
* Rendering loop
*------------------------------------------------------------------------
*/

glutMainLoop();

return 0;

}

void initGates(stateVar g_h, stateVar gOut_d, stateVar gIn_d,
  int memSize, REAL *J_current_d) {

  /*------------------------------------------------------------------------
  * Initialize host arrays
  *------------------------------------------------------------------------
  */

  #ifdef LOAD_DATA

    printf("Loading data...\n");
    loadData(g_h);

  #else

    int i, j, k, idx;

    // Array initialization
    for (k=0;k<nz;k++) {
      for (j=0;j<ny;j++) {
        for (i=0;i<nx;i++) {
          idx = i + nx*j + nx*ny*k;
          g_h.u[idx] = 0.f;
          g_h.v[idx] = 1.f;
          g_h.w[idx] = 0.f;
        }
      }
    }

    // Initial condition
    for (k=(int)floor(1);k<(int)floor(nz-1);k++) {
      for (j=(int)floor(1);j<(int)floor(ny/2-10);j++) {
        for (i=(int)floor(1);i<(int)floor(nx-1);i++) {
          idx = i + nx*j + nx*ny*k;
          g_h.u[idx] = 1.0f;
        }
      }
    }

  #endif

  /*------------------------------------------------------------------------
  * Initialize device arrays to 0
  *------------------------------------------------------------------------
  */

  CudaSafeCall(cudaMemset(gIn_d.u, 0.0f, param.memSize));
  CudaSafeCall(cudaMemset(gIn_d.v, 0.0f, param.memSize));
  CudaSafeCall(cudaMemset(gIn_d.w, 0.0f, param.memSize));

  CudaSafeCall(cudaMemset(gOut_d.u, 0.0f, param.memSize));
  CudaSafeCall(cudaMemset(gOut_d.v, 0.0f, param.memSize));
  CudaSafeCall(cudaMemset(gOut_d.w, 0.0f, param.memSize));

  CudaSafeCall(cudaMemset(J_current_d, 0.0f, param.memSize));

  /*------------------------------------------------------------------------
  * Copy form host to device
  *------------------------------------------------------------------------
  */

  // Copy data from host to device
  CudaSafeCall(cudaMemcpy(gIn_d.u, g_h.u, param.memSize, cudaMemcpyHostToDevice));
  CudaSafeCall(cudaMemcpy(gIn_d.v, g_h.v, param.memSize, cudaMemcpyHostToDevice));
  CudaSafeCall(cudaMemcpy(gIn_d.w, g_h.w, param.memSize, cudaMemcpyHostToDevice));

}

void loadData(stateVar g_h) {

  /*------------------------------------------------------------------------
  * Load initial conditions
  *------------------------------------------------------------------------
  */

  int i, j, k, idx, idxp;
  float u, v, w;
  FILE *fp1;

  //fp1 = fopen("./initial_conditions/data3_clock_22.dat","r");
  fp1 = fopen(param.initDataName,"r");
  //fp1 = fopen("./initial_conditions/rotation/data3rot315_clock_50.dat","r");

  if (fp1==NULL) {
    puts("Error: can't open the file \n");
    exitProgram();
  }

  for (j=0;j<ny;j++) {
    for (i=0;i<nx;i++) {
      idx = i + nx * j;
      fscanf(fp1, "%f\t%f\t%f", &u, &v, &w);
      g_h.u[idx] = u;
      g_h.v[idx] = v;
      g_h.w[idx] = w;
    }
  }

  fclose(fp1);

 // Copy in the z direction

  for (k=1;k<nz;k++) {
    for (j=0;j<ny;j++) {
      for (i=0;i<nx;i++) {
            idxp = i + nx * (j + ny * (k-1));
            idx = i + nx * (j + ny * k);
            g_h.u[idx] = g_h.u[idxp];
            g_h.v[idx] = g_h.v[idxp];
            g_h.w[idx] = g_h.w[idxp];
         }
      }
    }
}

int initGL(int *argc, char **argv) {

  // Initialize GLUT callback functions
  glutInit(argc, argv);
  glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB);
  glutInitWindowSize(width_3d, height_3d);
  glutCreateWindow("CUDA volume rendering");

  glewInit();

  if (!glewIsSupported("GL_VERSION_2_0 GL_ARB_pixel_buffer_object")) {
  printf("Required OpenGL extensions missing.");
  exit(EXIT_SUCCESS);
  }

  printf("Starting GLUT main loop...\n");
  // This is the normal rendering path for VolumeRender
  glutDisplayFunc(display);
  glutKeyboardFunc(keyboard);
  glutMouseFunc(mouse);
  glutMotionFunc(motion);
  glutReshapeFunc(reshape);
  glutSpecialFunc(Turn);
  glutIdleFunc(idle);
  initPixelBuffer();
  glutCloseFunc(cleanup);

  return true;

}

void display(void) {

  // use OpenGL to build view matrix
  GLfloat modelView[16];
  glMatrixMode(GL_MODELVIEW);

  glPushMatrix();
  glLoadIdentity();
  glRotatef(-viewRotation.x, 1.0, 0.0, 0.0);
  glRotatef(-viewRotation.y, 0.0, 1.0, 0.0);
  glTranslatef(-viewTranslation.x, -viewTranslation.y, -viewTranslation.z);
  glGetFloatv(GL_MODELVIEW_MATRIX, modelView);
  glPopMatrix();

  invViewMatrix[0]  = modelView[0];
  invViewMatrix[1]  = modelView[4];
  invViewMatrix[2]  = modelView[8];
  invViewMatrix[3]  = modelView[12];
  invViewMatrix[4]  = modelView[1];
  invViewMatrix[5]  = modelView[5];
  invViewMatrix[6]  = modelView[9];
  invViewMatrix[7]  = modelView[13];
  invViewMatrix[8]  = modelView[2];
  invViewMatrix[9]  = modelView[6];
  invViewMatrix[10] = modelView[10];
  invViewMatrix[11] = modelView[14];

  if (animate) {

    animation(grid3D,block3D,gate_h,
      gateOut_d,gateIn_d,J_current_d,r_d,
      param,point_h,point_d,electrode,initConditionFlag);

  }

  /*------------------------------------------------------------------------
  * Conduction block (initial condition)
  *-------------------------------------------------------------------------
  */
/*
  // Transform to pixel number
  param.conductionBlockPixel = initSinglePoint(param.conductionBlockPoint, param);
  // Measure voltage at the previous point to apply condution block
  point_h2 = singlePoint(gateIn_d,point_h2,point_d,param.conductionBlockPixel);

  // Apply condution block
  if ((initConditionFlag == true) && (point_h2[0] > 0.5)) {

    printf("Conduction block point: (%f,%f,%f)\n\n",
      param.conductionBlockPoint.x,param.conductionBlockPoint.y,param.conductionBlockPoint.z);
    cutVoltage(param,gate_h,gateIn_d);
    initConditionFlag = false;
    //tipTraFlag = 2;

    }
*/

  /*------------------------------------------------------------------------
  * Switch between voltage and filament screen
  *-------------------------------------------------------------------------
  */

  switch (tipTraFlag) {
    case 1:

      copyRender(grid1D,block1D,param.totpoints,gateIn_d,h_volume);

    break;
    case 2:

    if ( param.count%param.sampleRate == 0 ) {

      CudaSafeCall(cudaMemset(h_volume, 0, size));

      h_volume = spiralTip(grid3Dz,block3Dz,v_past_d,gateIn_d,h_volume);

      CudaSafeCall(cudaMemcpy(v_past_d, gateIn_d.u, param.memSize,
        cudaMemcpyDeviceToDevice));

      int dsize;
      cudaMemcpyFromSymbol(&dsize, dev_count, sizeof(int));
      dsizeTip.push_back(dsize);
      printf("%d\n", dsize);

    }

    break;

    default:
      puts("Display function: option not available");
    break;

    }

  /*------------------------------------------------------------------------
  * Simulation time and simulation time limit
  *------------------------------------------------------------------------
  */  

    param.count += ITPERFRAME;
    param.t = param.count*param.dt;

  if (param.t > param.tlim) exitProgram();

  /*------------------------------------------------------------------------
  * Rendering process
  *------------------------------------------------------------------------
  */

  initCuda(volumeSize, h_volume);

  //CudaSafeCall(cudaFree(h_volume));
  //CudaSafeCall(cudaMemset(h_volume, 0, size));

  render();

  // display results
  glClear(GL_COLOR_BUFFER_BIT);

  // draw image from PBO
  glDisable(GL_DEPTH_TEST);

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  /*
  #if 0
      // draw using glDrawPixels (slower)
      glRasterPos2i(0, 0);
      glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, pbo);
      glDrawPixels(width_3d, height_3d, GL_RGBA, GL_UNSIGNED_BYTE, 0);
      glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, 0);
  #else
  */

  // draw using texture
  //
  // copy from pbo to texture
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, pbo);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width_3d, height_3d, GL_RGBA,
    GL_UNSIGNED_BYTE, 0);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, 0);

  // draw textured quad
  glEnable(GL_TEXTURE_2D);
  glBegin(GL_QUADS);
  glTexCoord2f(1, 0);
  glVertex2f(1, 0);
  glTexCoord2f(1, 1);
  glVertex2f(1, 1);
  glTexCoord2f(0, 1);
  glVertex2f(0, 1);
  glTexCoord2f(0, 0);
  glVertex2f(0, 0);

  glEnd();
  glDisable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, 0);
  //#endif

  //Draw_Axes();

  glutSwapBuffers();
  glutReportErrors();

  /*------------------------------------------------------------------------
  * Calculate FPS
  *------------------------------------------------------------------------
  */

  computeFPS();

}

void Draw_Axes(void) {

  //glMatrixMode(GL_MODELVIEW);

  glPushMatrix ();

  //glTranslatef(viewTranslation.x + 0.5, viewTranslation.y + 0.5, viewTranslation.z/10.f);
  glTranslatef (0.5, 0.5, -0.5);
  glRotatef(viewRotation.x, 1.0, 0.0, 0.0);
  glRotatef(viewRotation.y, 0.0, 1.0, 0.0);
  //glScalef (0.25, 0.25, 0.25);
  //glGetFloatv(GL_MODELVIEW_MATRIX, modelView);
  //glRotatef(-viewRotation.z, 0.0, 0.0, 1.0);


  glLineWidth (2.0);

  glBegin(GL_LINES);
  //glColor3f (1,0,0); // X axis is red.
  glVertex3f(-0.35f,-0.35f,0.0f);
  glVertex3f(-0.25f,-0.35f,0.0f);
  //glColor3f (0,1,0); // Y axis is green.
  glVertex3f(-0.35f,-0.35f,0.0f);
  glVertex3f(-0.35f,-0.35f,0.1f);
  //glColor3f (0,0,1); // z axis is blue.
  glVertex3f(-0.35f,-0.35f,0.0f);
  glVertex3f(-0.35f,-0.25f,0.0f);

/*
  glLineWidth (2.0);
  //glColor3f (0.0, 0.2, 0.9);
  glutWireTeapot (0.1);
  glGetFloatv(GL_MODELVIEW_MATRIX, modelView);
*/

  glEnd();
  glPopMatrix();

}

void Turn(int key, int x, int y) {

switch (key) {

    case GLUT_KEY_RIGHT: viewRotation.y += 5; break;
    case GLUT_KEY_LEFT : viewRotation.y -= 5; break;
    case GLUT_KEY_UP : viewRotation.x -= 5; break;
    case GLUT_KEY_DOWN : viewRotation.x += 5; break;

  }
}

void render(void) {

  /*------------------------------------------------------------------------
  * Render image using CUDA
  *------------------------------------------------------------------------
  */

  copyInvViewMatrix(invViewMatrix, sizeof(float4)*3);

  // map PBO to get CUDA device pointer
  uint *d_output;
  // map PBO to get CUDA device pointer
  CudaSafeCall(cudaGraphicsMapResources(1, &cuda_pbo_resource, 0));
  size_t num_bytes;
  CudaSafeCall(cudaGraphicsResourceGetMappedPointer((void **)&d_output,
  &num_bytes, cuda_pbo_resource));
  //printf("CUDA mapped PBO: May access %ld bytes\n", num_bytes);

  // clear image
  CudaSafeCall(cudaMemset(d_output, 0, width_3d*height_3d*4));

  // call CUDA kernel, writing results to PBO
  render_kernel(tipTraFlag, gridSize, blockSize, d_output, width_3d,
    height_3d, density, brightness, transferOffset, transferScale);

  CudaSafeCall(cudaGraphicsUnmapResources(1, &cuda_pbo_resource, 0));
}

void keyboard(unsigned char key, int x, int y) {

  switch (key) {
    case 27:
      exitProgram();
    break;
    case '1':
      tipTraFlag = 1;
      puts("Voltage visualization:");
    break;
    case '2':
      tipTraFlag = 2;
      puts("Spiral filament visualization:");
    break;
    case 'f':
      linearFiltering = !linearFiltering;
      setTextureFilterMode(linearFiltering);
    break;
    case '+':
      density += 0.01f;
    break;
    case '-':
      density -= 0.01f;
    break;
    case ']':
      brightness += 0.1f;
    break;
    case '[':
      brightness -= 0.1f;
      break;
    case ';':
      transferOffset += 0.01f;
    break;
    case '\'':
      transferOffset -= 0.01f;
    break;
    case '.':
      transferScale += 0.01f;
    break;
    case ',':
      transferScale -= 0.01f;
    break;
    case '/':
      cutVoltage(param, gate_h, gateIn_d);
    break;
    case 'v':
      stimulateV(param.memSize, gate_h, gateIn_d);
    break;
    case ' ':
      animate =! animate;
    break;
    case 's':
      screenShot(width_3d, height_3d);
    break;

    default:
      puts("Not a keyboard option");
    break;
    }

  printf("density = %.2f, brightness = %.2f, transferOffset = %.2f, transferScale = %.2f\n",
    density, brightness, transferOffset, transferScale);
  glutPostRedisplay();

}

void mouse(int button, int state, int x, int y) {

  if (state == GLUT_DOWN) {
    buttonState  |= 1<<button;
    }
  else if (state == GLUT_UP) {
    buttonState = 0;
    }

  ox = x;
  oy = y;

  glutPostRedisplay();

}

void motion(int x, int y) {

  float dx, dy;
  dx = (float)(x - ox);
  dy = (float)(y - oy);

  if (buttonState == 4) {
    // right = zoom
    viewTranslation.z += dy / 100.0f;
    }
  else if (buttonState == 2) {
      // middle = translate
    viewTranslation.x += dx / 100.0f;
    viewTranslation.y -= dy / 100.0f;
    }
  else if (buttonState == 1) {
    // left = rotate
    viewRotation.x += dy / 5.0f;
    viewRotation.y += dx / 5.0f;
  }

  ox = x;
  oy = y;

  glutPostRedisplay();

}

void reshape(int w, int h) {

  width_3d = w;
  height_3d = h;
  initPixelBuffer();

  // calculate new grid size
  //gridSize = dim3(iDivUp(width_3d, blockSize.x), iDivUp(height_3d,
  //blockSize.y));

  glViewport(0, 0, w, h);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();

  glOrtho(0.0, 1.0, 0.0, 1.0, 0.0, 1.0);
  //glFrustum(1.0, -1.0, 1.0, 0.0, -1.0, -1.0);

}

void initPixelBuffer(void) {

  if (pbo) {
    // unregister this buffer object from CUDA C
    CudaSafeCall(cudaGraphicsUnregisterResource(cuda_pbo_resource));

    // delete old buffer
    glDeleteBuffers(1, &pbo);
    glDeleteTextures(1, &tex);
  }

  // create pixel buffer object for display
  glGenBuffers(1, &pbo);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, pbo);
  glBufferData(GL_PIXEL_UNPACK_BUFFER_ARB, width_3d*height_3d*sizeof(GLubyte)*4,
    0, GL_STREAM_DRAW_ARB);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER_ARB, 0);

  // register this buffer object with CUDA
  CudaSafeCall(cudaGraphicsGLRegisterBuffer(&cuda_pbo_resource, pbo,
    cudaGraphicsMapFlagsWriteDiscard));

  // create texture for display
  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width_3d, height_3d, 0, GL_RGBA,
    GL_UNSIGNED_BYTE, NULL);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glBindTexture(GL_TEXTURE_2D, 0);

}

void idle(void) {

  glutPostRedisplay();

}

void cleanup(void) {

  freeCudaBuffers();

  if (pbo) {
    cudaGraphicsUnregisterResource(cuda_pbo_resource);
    glDeleteBuffers(1, &pbo);
    glDeleteTextures(1, &tex);
    }

  /*
  if (g_pVertices)
  {
      delete [] g_pVertices;
      g_pVertices = NULL;
  }
  */
  // Calling cudaProfilerStop causes all profile data to be
  // flushed before the application exits

  CudaSafeCall(cudaProfilerStop());
}

// Print final data and exit application cleanly
void exitProgram(void) {

  CudaSafeCall(cudaMemcpy(gate_h.u, gateIn_d.u, param.memSize,
    cudaMemcpyDeviceToHost));
  CudaSafeCall(cudaMemcpy(gate_h.v, gateIn_d.v, param.memSize,
    cudaMemcpyDeviceToHost));
  CudaSafeCall(cudaMemcpy(gate_h.w, gateIn_d.w, param.memSize,
    cudaMemcpyDeviceToHost));
  

  puts("\n");

  #ifdef SAVE_DATA

  //print1D(gate_h,param.count,strAdress,sbytes);
  //print2D(gate_h,param.count,strAdress,sbytes);
  //print3D(gate_h,param.count,strAdress,sbytes);

  printVoltageInTime(electrode,strAdress,sbytes,param.dt,param.count);
  printTip(dsizeTip,strAdress,sbytes);
  printParameters(param,strAdress,sbytes);

  #endif


  // Free gate host and device memory
  free(gate_h.u);
  free(gate_h.v);
  free(gate_h.w);
  free(point_h);

  CudaSafeCall(cudaFree(gateIn_d.u));
  CudaSafeCall(cudaFree(gateIn_d.v));
  CudaSafeCall(cudaFree(gateIn_d.w));
  CudaSafeCall(cudaFree(gateOut_d.u));
  CudaSafeCall(cudaFree(gateOut_d.v));
  CudaSafeCall(cudaFree(gateOut_d.w));
  CudaSafeCall(cudaFree(J_current_d));
  CudaSafeCall(cudaFree(v_past_d));
  CudaSafeCall(cudaFree(point_d));

  #ifdef ANISOTROPIC_TISSUE

  free(r.x);
  free(r.y);
  free(r.z);
  free(r.xy);
  free(r.bx);
  free(r.by);

  CudaSafeCall(cudaFree(r_d.x));
  CudaSafeCall(cudaFree(r_d.y));
  CudaSafeCall(cudaFree(r_d.z));
  CudaSafeCall(cudaFree(r_d.xy));
  CudaSafeCall(cudaFree(r_d.bx));
  CudaSafeCall(cudaFree(r_d.by));

  #endif

  glutDestroyWindow(glutGetWindow());

  cudaDeviceReset();

  printf("Physical time: %.0f ms , Computer time: %.1f s", param.physicalTime, param.tiempo);

  puts("\nSimulation ended !!!!!\n");

  exit(0);

}

void computeFPS(void) {

  GLint64 timer;
  glGetInteger64v(GL_TIMESTAMP, &timer);

  if (first) {
    param.base = timer*0.000000001;
    param.frameCount = 0;
    param.tiempo = timer*0.000000001-param.base;
    starttime = param.tiempo;
    first = false;
    return;
    }

  param.tiempo = timer*0.000000001-param.base;
  frames++;

  if (param.tiempo - starttime > 1.0 && frames > 10) {
    param.fpsCount = (double) frames / (param.tiempo - starttime);
    starttime = param.tiempo;
    frames = 0;
    }

  param.frameCount++;

  if (animate) param.physicalTime = param.dt*param.count;

  char fps[256];
  sprintf(fps, "Frame: %d , %0.1f fps , physical time: %.0f ms , Computer time: %.1f s",
    param.frameCount, param.fpsCount, param.physicalTime, param.tiempo);
  glutSetWindowTitle(fps);
}
