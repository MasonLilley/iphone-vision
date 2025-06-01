import cv2
import numpy as np
import os
import sys
import platform

def print_section_header(title):
    print("\n" + "="*50)
    print(f" {title}")
    print("="*50)

def check_opencv_version():
    print_section_header("OpenCV Information")
    print(f"OpenCV Version: {cv2.__version__}")
    
    # Check how OpenCV was built
    print("\nBuild Information:")
    for item in dir(cv2.getBuildInformation()):
        if not item.startswith("__"):
            print(f"  {item}: {getattr(cv2.getBuildInformation(), item)}")

def check_cuda_support():
    print_section_header("CUDA Support")
    
    # Check if CUDA is available in OpenCV
    cuda_available = hasattr(cv2, 'cuda') and hasattr(cv2.cuda, 'getCudaEnabledDeviceCount')
    print(f"CUDA Module Available: {cuda_available}")
    
    if cuda_available:
        try:
            device_count = cv2.cuda.getCudaEnabledDeviceCount()
            print(f"CUDA Devices Found: {device_count}")
            
            if device_count > 0:
                # Get compute capability
                print("\nCUDA Device Information:")
                for i in range(device_count):
                    cv2.cuda.setDevice(i)
                    print(f"  Device {i}:")
                    print(f"    Name: {cv2.cuda.getDeviceName(i)}")
                    print(f"    Free Memory: {cv2.cuda.DeviceInfo().freeMemory() / (1024*1024):.2f} MB")
                    print(f"    Total Memory: {cv2.cuda.DeviceInfo().totalMemory() / (1024*1024):.2f} MB")
                    print(f"    Compute Capability: {cv2.cuda.DeviceInfo().majorVersion()}.{cv2.cuda.DeviceInfo().minorVersion()}")
                    print(f"    Multi-Processor Count: {cv2.cuda.DeviceInfo().multiProcessorCount()}")
                    print(f"    Async Engine Count: {cv2.cuda.DeviceInfo().asyncEngineCount()}")
                    print(f"    Concurrent Kernels Supported: {cv2.cuda.DeviceInfo().concurrentKernels()}")
            else:
                print("No CUDA devices detected despite CUDA being enabled in OpenCV.")
        except Exception as e:
            print(f"Error accessing CUDA information: {e}")
    else:
        print("OpenCV was built without CUDA support.")

def check_opencl_support():
    print_section_header("OpenCL Support")
    
    print(f"OpenCL Available: {cv2.ocl.haveOpenCL()}")
    print(f"OpenCL Currently In Use: {cv2.ocl.useOpenCL()}")
    
    if cv2.ocl.haveOpenCL():
        cv2.ocl.setUseOpenCL(True)
        print(f"OpenCL After Enabling: {cv2.ocl.useOpenCL()}")
        
        # Get platform and device info
        try:
            platforms = cv2.ocl.getPlatforms()
            print(f"\nOpenCL Platforms Found: {len(platforms)}")
            
            for i, platform in enumerate(platforms):
                print(f"\n  Platform {i}: {platform.name()}")
                devices = platform.getDevices()
                print(f"  Devices Found: {len(devices)}")
                
                for j, device in enumerate(devices):
                    print(f"    Device {j}: {device.name()}")
                    print(f"      Vendor: {device.vendor()}")
                    print(f"      Version: {device.version()}")
                    print(f"      Type: {device.type()}")
                    print(f"      Driver Version: {device.driverVersion()}")
                    print(f"      Max Compute Units: {device.maxComputeUnits()}")
                    print(f"      Global Memory Size: {device.globalMemSize() / (1024*1024):.2f} MB")
                    print(f"      Local Memory Size: {device.localMemSize() / 1024:.2f} KB")
        except Exception as e:
            print(f"Error accessing OpenCL information: {e}")

def run_cuda_test():
    print_section_header("CUDA Functionality Test")
    
    if not hasattr(cv2, 'cuda') or not hasattr(cv2.cuda, 'getCudaEnabledDeviceCount'):
        print("Cannot run CUDA test: OpenCV was built without CUDA support.")
        return
        
    if cv2.cuda.getCudaEnabledDeviceCount() == 0:
        print("Cannot run CUDA test: No CUDA devices available.")
        return
        
    try:
        print("Creating test matrices...")
        # Create a CPU matrix
        cpu_mat = np.random.randint(0, 256, (2000, 2000), dtype=np.uint8)
        
        # Start timer
        start_time_cpu = cv2.getTickCount()
        
        # CPU operation
        cpu_result = cv2.GaussianBlur(cpu_mat, (5, 5), 0)
        
        # Calculate CPU time
        cpu_time = (cv2.getTickCount() - start_time_cpu) / cv2.getTickFrequency()
        print(f"CPU Gaussian Blur Time: {cpu_time:.6f} seconds")
        
        # Test CUDA operations
        start_time_gpu = cv2.getTickCount()
        
        # Upload to GPU
        gpu_mat = cv2.cuda_GpuMat()
        gpu_mat.upload(cpu_mat)
        
        # GPU operation
        gpu_filter = cv2.cuda.createGaussianFilter(cv2.CV_8UC1, cv2.CV_8UC1, (5, 5), 0)
        gpu_result = gpu_filter.apply(gpu_mat)
        
        # Download result
        cuda_result = gpu_result.download()
        
        # Calculate GPU time
        gpu_time = (cv2.getTickCount() - start_time_gpu) / cv2.getTickFrequency()
        print(f"GPU Gaussian Blur Time: {gpu_time:.6f} seconds")
        
        # Calculate speedup
        speedup = cpu_time / gpu_time
        print(f"GPU Speedup: {speedup:.2f}x faster than CPU")
        
        # Verify results are similar
        diff = cv2.absdiff(cpu_result, cuda_result)
        print(f"Max Difference Between CPU and GPU Results: {np.max(diff)}")
        print(f"CUDA Test Result: {'Successful' if np.max(diff) < 5 else 'Failed - Results Differ Significantly'}")
        
    except Exception as e:
        print(f"CUDA test failed with error: {e}")
        import traceback
        traceback.print_exc()

def system_info():
    print_section_header("System Information")
    print(f"Python Version: {platform.python_version()}")
    print(f"OS: {platform.system()} {platform.release()}")
    print(f"Machine: {platform.machine()}")
    print(f"Processor: {platform.processor()}")
    
    # Try to get NVIDIA driver information if on Linux
    if platform.system() == 'Linux':
        try:
            nvidia_smi = os.popen('nvidia-smi --query-gpu=driver_version,name,memory.total --format=csv,noheader').read().strip()
            if nvidia_smi:
                print("\nNVIDIA Driver Information:")
                for i, line in enumerate(nvidia_smi.split('\n')):
                    print(f"  GPU {i}: {line}")
        except:
            pass

if __name__ == "__main__":
    system_info()
    check_opencv_version()
    check_cuda_support()
    check_opencl_support()
    run_cuda_test()
    
    print("\n" + "="*50)
    print(" Summary ")
    print("="*50)
    cuda_available = hasattr(cv2, 'cuda') and cv2.cuda.getCudaEnabledDeviceCount() > 0
    opencl_available = cv2.ocl.haveOpenCL() and cv2.ocl.useOpenCL()
    
    print(f"OpenCV: v{cv2.__version__}")
    print(f"CUDA Support: {'✓' if cuda_available else '✗'}")
    print(f"OpenCL Support: {'✓' if opencl_available else '✗'}")
    
    if not cuda_available and not opencl_available:
        print("\nRecommendation: Install OpenCV with GPU acceleration for better performance")
    elif cuda_available:
        print("\nYour OpenCV installation has CUDA support - optimal for Jetson platforms")