import asyncio
import websockets
import numpy as np
import cv2
import time
import visionProcessing as vp

async def display_image(websocket, path):
    frame_count = 0
    start_time = time.time()

    while True:
        # binary data -> numpy array -> opencv decodes it
        binary_data = await websocket.recv()
        np_array = np.frombuffer(binary_data, dtype=np.uint8)
        image = cv2.imdecode(np_array, cv2.IMREAD_COLOR)

        if image is not None:
            frame_count += 1
            
            image = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
            cv2.putText(image, f"FPS: {frame_count / (time.time() - start_time):.2f}", 
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
            
            #Image processing in seperate file
            image = vp.processImage(image)
            
            cv2.imshow("Received Image", image)
            cv2.waitKey(1) 
        else:
            print("Failed to decode image")

        #FPS calculator
        if time.time() - start_time >= 1:
            frame_count = 0
            start_time = time.time()

async def main():
    async with websockets.serve(display_image, "0.0.0.0", 6789):
        print("Server started at ws://0.0.0.0:6789")
        await asyncio.Future()

if __name__ == "__main__":
    cv2.namedWindow("Received Image", cv2.WINDOW_NORMAL)
    asyncio.run(main())