import asyncio
import websockets
import numpy as np
import cv2
import time
from concurrent.futures import ThreadPoolExecutor
import os
import poseestimation

# Try different decoders in order of speed
try:
    from turbojpeg import TurboJPEG
    jpeg = TurboJPEG()
    print("Using TurboJPEG decoder")
    
    def decode_jpeg(binary_data):
        return jpeg.decode(binary_data)
        
except ImportError:
    try:
        import av
        print("Using PyAV decoder")
        
        def decode_jpeg(binary_data):
            with av.open(io.BytesIO(binary_data), 'r') as container:
                for frame in container.decode(video=0):
                    return frame.to_ndarray(format='bgr24')
    except ImportError:
        from PIL import Image
        import io
        print("Falling back to PIL decoder")
        
        def decode_jpeg(binary_data):
            pil_image = Image.open(io.BytesIO(binary_data))
            return cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)

# Enable hardware acceleration
cv2.ocl.setUseOpenCL(True)
print(f"OpenCL is enabled: {cv2.ocl.useOpenCL()}")

# Use environment variables to enable hardware acceleration
os.environ['OPENCV_OPENCL_RUNTIME'] = 'opencl'
os.environ['OPENCV_OPENCL_DEVICE'] = '0'  # Use first GPU device

# Number of workers for the thread pool
NUM_WORKERS = max(2, os.cpu_count() // 2)
executor = ThreadPoolExecutor(max_workers=NUM_WORKERS)
print(f"Using {NUM_WORKERS} worker threads")

async def display_image(websocket, queue):
    frame_count = 0
    start_time = time.time()
    fps_update_interval = 0.5  # Update FPS display every 0.5 seconds
    last_fps_time = start_time
    current_fps = 0
    
    # Pre-allocate OpenCV text parameters for faster rendering
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.7
    font_color = (0, 0, 255)
    line_type = 2
    text_position = (10, 30)

    try:
        while True:
            binary_data = await queue.get()  # Get the latest data from the queue
            
            # Skip processing if we're more than N frames behind
            if queue.qsize() > 2:
                print(f"Skipping frame, {queue.qsize()} frames behind")
                continue
                
            current_time = time.time()
            decode_start = current_time
            
            # Decode the image asynchronously
            image = await asyncio.get_event_loop().run_in_executor(
                executor, decode_jpeg, binary_data)
            
            decode_time = time.time() - decode_start
            
            if image is not None:
                frame_count += 1
                
                # Rotate the image - this is an expensive operation, consider if it's necessary
                image = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
                image = poseestimation.drawPose(image, draw_stats=True)
                
                # Calculate and update FPS less frequently to reduce overhead
                if current_time - last_fps_time >= fps_update_interval:
                    current_fps = frame_count / (current_time - last_fps_time)
                    frame_count = 0
                    last_fps_time = current_time
                
                # Only add FPS text on frames we actually show
                cv2.putText(image, f"FPS: {current_fps:.1f} Decode: {decode_time*1000:.1f}ms", 
                            text_position, font, font_scale, font_color, line_type)
                
                # Use non-blocking imshow
                cv2.imshow("Received Image", image)
                cv2.waitKey(1)
            else:
                print("Failed to decode image")
                
    except websockets.exceptions.ConnectionClosedOK:
        print("connection closed gracefully")
    except Exception as e:
        print(f"Display error: {e}")

async def receive_data(websocket, queue):
    try:
        while True:
            binary_data = await websocket.recv()
            
            # Aggressive frame dropping - keep queue size small for lower latency
            if queue.qsize() >= 1:
                try:
                    # Clear the queue completely to avoid processing stale frames
                    while not queue.empty():
                        await queue.get()
                except asyncio.QueueEmpty:
                    pass
            
            await queue.put(binary_data)
    except Exception as e:
        print(f"Receive error: {e}")

async def handle_connection(websocket):
    # Smaller queue size for lower latency
    queue = asyncio.Queue(maxsize=2)
    
    # Set higher priority for consumer vs producer
    consumer_task = asyncio.create_task(display_image(websocket, queue))
    producer_task = asyncio.create_task(receive_data(websocket, queue))
    
    try:
        # Wait for both tasks to complete
        await asyncio.gather(consumer_task, producer_task)
    except websockets.exceptions.ConnectionClosedOK:
        print("Connection closed gracefully")
    except Exception as e:
        print(f"Connection error: {e}")
    finally:
        consumer_task.cancel()
        producer_task.cancel()

async def main():
    # Create window before starting server to avoid lag on first frame
    cv2.namedWindow("Received Image", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Received Image", 640, 480)
    
    print("Starting server...")
    async with websockets.serve(handle_connection, "0.0.0.0", 6789):
        print("Server started at ws://0.0.0.0:6789")
        await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Server stopped by user")
    finally:
        cv2.destroyAllWindows()