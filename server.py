import asyncio
import websockets
import numpy as np
import cv2
import time
import visionProcessing as vp
from concurrent.futures import ThreadPoolExecutor
# import faceRecognition as faces

cv2.ocl.setUseOpenCL(True)
print("OpenCL is enabled:", cv2.ocl.useOpenCL())
async def display_image(websocket, queue):
    frame_count = 0
    start_time = time.time()

    try:
        while True:
            binary_data = await queue.get()  # Get the latest data from the queue
            image = await decode_image(binary_data)
            
            image = vp.processImage(image)

            if image is not None:
                frame_count += 1
                
                image = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
                cv2.putText(image, f"FPS: {frame_count / (time.time() - start_time):.2f}", 
                            (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
                
                # Image processing in separate file
                # image = faces.recognize_face_in_image(image)
                
                cv2.imshow("Received Image", image)
                
                cv2.waitKey(1) 
            else:
                print("Failed to decode image")

            # FPS calculator
            if time.time() - start_time >= 1:
                frame_count = 0
                start_time = time.time()
    except websockets.exceptions.ConnectionClosedOK:
        print("connection closed gracefully")

executor = ThreadPoolExecutor(max_workers=2)

async def decode_image(binary_data):
    loop = asyncio.get_event_loop()
    np_array = np.frombuffer(binary_data, dtype=np.uint8)
    return await loop.run_in_executor(executor, lambda: cv2.imdecode(np_array, cv2.IMREAD_COLOR))

async def receive_data(websocket, queue):
    while True:
        binary_data = await websocket.recv()
        
        if queue.full():
            await queue.get()  # Discard the oldest frame
        
        await queue.put(binary_data)  # Add the new data to the queue

async def handle_connection(websocket):
    queue = asyncio.Queue(maxsize=1)  # Keep only the latest frame. If there's delay in connection, don't show old frames
    consumer_task = asyncio.create_task(display_image(websocket, queue))
    producer_task = asyncio.create_task(receive_data(websocket, queue))
    
    try:
        await asyncio.gather(consumer_task, producer_task)
    except websockets.exceptions.ConnectionClosedOK:
        print("Connection closed gracefully dubs")
    except Exception as e:
        print(f"Error in handle_connection: {e}")
    finally:
        consumer_task.cancel()


async def main():
    async with websockets.serve(handle_connection, "0.0.0.0", 6789):
        print("Server started at ws://0.0.0.0:6789")
        await asyncio.Future()

if __name__ == "__main__":
    cv2.namedWindow("Received Image", cv2.WINDOW_NORMAL)
    asyncio.run(main())
