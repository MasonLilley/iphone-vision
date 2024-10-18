import cv2
from matplotlib import pyplot as plt

import time

face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_eye.xml')

cap = cv2.VideoCapture(2)

print(cv2.data.haarcascades)

cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
cap.set(cv2.CAP_PROP_FPS, 120)

if not cap.isOpened():
    print("Cannot open camera")
    exit()

fps = 0
frame_count = 0
start_time = time.time()

while True:    
    ret, frame = cap.read()
    
    # frame = cv2.imread('license_plate.jpeg')
    
    assert ret is not None, "Didn't receive frame, exiting..."
    
    faces = face_cascade.detectMultiScale(frame, scaleFactor=4, minNeighbors=10)

    for (x, y, w, h) in faces:
            center = (x + w // 2, y + h // 2)
            radius = int((w + h) // 4)  # Calculate radius based on width and height
            cv2.circle(frame, center, radius, (0, 255, 0), 3)  # Draw a green circle


    elapsed_time = time.time() - start_time
    if elapsed_time > 1.0:
        fps = frame_count / elapsed_time
        frame_count = 0
        start_time = time.time()

    cv2.putText(frame, f'FPS: {fps:.2f}', (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)

    cv2.imshow('Stream', frame)

    frame_count += 1

    if cv2.waitKey(1) == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()