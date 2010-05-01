#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <assert.h>

//#include <cutil_inline.h>

//#include <culapack.h>
//#include <culapackdevice.h>

#define imin(X, Y)  ((X) < (Y) ? (X) : (Y))

__device__ inline float MoroInvCNDgpu(float P){
    const float a1 = 2.50662823884f;
    const float a2 = -18.61500062529f;
    const float a3 = 41.39119773534f;
    const float a4 = -25.44106049637f;
    const float b1 = -8.4735109309f;
    const float b2 = 23.08336743743f;
    const float b3 = -21.06224101826f;
    const float b4 = 3.13082909833f;
    const float c1 = 0.337475482272615f;
    const float c2 = 0.976169019091719f;
    const float c3 = 0.160797971491821f;
    const float c4 = 2.76438810333863E-02f;
    const float c5 = 3.8405729373609E-03f;
    const float c6 = 3.951896511919E-04f;
    const float c7 = 3.21767881768E-05f;
    const float c8 = 2.888167364E-07f;
    const float c9 = 3.960315187E-07f;
    float y, z;

    if(P <= 0 || P >= 1.0f)
        return __int_as_float(0x7FFFFFFF);

    y = P - 0.5f;
    if(fabsf(y) < 0.42f){
        z = y * y;
        z = y * (((a4 * z + a3) * z + a2) * z + a1) / ((((b4 * z + b3) * z + b2) * z + b1) * z + 1.0f);
    }else{
        if(y > 0)
            z = __logf(-__logf(1.0f - P));
        else
            z = __logf(-__logf(P));

        z = c1 + z * (c2 + z * (c3 + z * (c4 + z * (c5 + z * (c6 + z * (c7 + z * (c8 + z * c9)))))));
        if(y < 0) z = -z;
    }

    return z;
}

__global__ void NormalDistribution(float *A, int N)
{
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i < N)
        A[i] = MoroInvCNDgpu(A[i]);
}

__global__ void CumSum(float *A, int N)
{
    float *B = A + (threadIdx.x)*N;
    float cumsum = 0;
    for(int i=0; i<N; i++){
        cumsum += B[i];
        B[i] = cumsum;
    }  
}

void UniformDistribution(float *A, int M, int N)
{
	int i,j;
	for(i=0; i<M; i++){
		for(j=0; j<N; j++){
			A[i+j*M] = (float) rand() / RAND_MAX;
		}
	}
}


void OutputMatrix(char *fileName, float *A, int M, int N){
    FILE *fp;
    fp = fopen(fileName, "w");

    int i,j;
    for(i=0; i<M; i++){
        for(j=0; j<N; j++){
            fprintf(fp, "%f ", A[i+j*M]);
        }
        fprintf(fp, "\n");
    } 

    fclose(fp);
}

int main(){

    srand(time(0));

    int n = 1000;
    int N = 16;

    int length = n*(N-1);
    size_t size = length*sizeof(float);

    float *dW = (float*) malloc( size );
    UniformDistribution(dW, n, N-1);

    float *dW_d;
    cudaMalloc( (void**) &dW_d, size);
    cudaMemcpy(dW_d, dW, size, cudaMemcpyHostToDevice);

    int threadsPerBlock = 256;
    int blocksPerGrid = (n*N + threadsPerBlock - 1) / threadsPerBlock;
    
    NormalDistribution<<<blocksPerGrid, threadsPerBlock>>>(dW_d, length); 
    
    cudaMemcpy(dW, dW_d, size, cudaMemcpyDeviceToHost);
    cudaFree(dW_d);

    OutputMatrix("dW_gpu.mat", dW, n, N-1); 

    free(dW);

    dW = (float*) malloc(size);
    
    for(int i=0; i<N-1; i++){
        for(int j=0; j<n; j++){
            dW[i*n+j] = j;
        }
    }

    OutputMatrix("init_scan.mat", dW, n, N-1);

    cudaMalloc( (void**) &dW_d, size);
    cudaMemcpy(dW_d, dW, size, cudaMemcpyHostToDevice);
    
    CumSum<<<1, N-1>>>(dW_d, n);     
    
    cudaMemcpy(dW, dW_d, size, cudaMemcpyDeviceToHost);
    cudaFree(dW_d);

    OutputMatrix("scan_gpu.mat", dW, n, N-1); 

    free(dW); 

     

}

