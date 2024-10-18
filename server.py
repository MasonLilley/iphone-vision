import asyncio
import websockets
import numpy as np
import cv2

async def display_image(websocket, path):
    while True:
        binary_data = await websocket.recv()

        np_array = np.frombuffer(binary_data, dtype=np.uint8)

        image = cv2.imdecode(np_array, cv2.IMREAD_COLOR)

        if image is not None:
            cv2.imshow("Received Image", image)
            cv2.waitKey(1) 
        else:
            print("Failed to decode image")

async def main():
    async with websockets.serve(display_image, "0.0.0.0", 6789):
        print("Server started at ws://0.0.0.0:6789")
        await asyncio.Future()

if __name__ == "__main__":
    cv2.namedWindow("Received Image", cv2.WINDOW_NORMAL)
    asyncio.run(main())
