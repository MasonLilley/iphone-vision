import cv2
import os
import numpy as np
from PIL import Image

print(cv2.__version__)


# Paths
dataset_path = "dataset"
trainer_path = "trainer/trainer.yml"
cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"

# Create necessary directories if they don't exist
if not os.path.exists(dataset_path):
    os.makedirs(dataset_path)
if not os.path.exists(os.path.dirname(trainer_path)):
    os.makedirs(os.path.dirname(trainer_path))

# Initialize face recognizer and detector
recognizer = cv2.face.LBPHFaceRecognizer_create()
face_cascade = cv2.CascadeClassifier(cascade_path)

# Function to capture face data
def capture_faces(user_id, sample_size=30):
    cam = cv2.VideoCapture(2)
    count = 0

    while True:
        ret, img = cam.read()
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(gray, 1.3, 5)

        for (x, y, w, h) in faces:
            cv2.rectangle(img, (x, y), (x + w, y + h), (255, 0, 0), 2)
            count += 1

            # Save the captured image in dataset folder
            cv2.imwrite(f"{dataset_path}/User.{user_id}.{count}.jpg", gray[y:y+h, x:x+w])

            cv2.imshow('Capturing Faces', img)

        if cv2.waitKey(100) & 0xFF == ord('q') or count >= sample_size:
            break

    cam.release()
    cv2.destroyAllWindows()
    print(f"\n[INFO] Captured {count} face samples for User {user_id}.")

def train_recognizer():
    image_paths = [os.path.join(dataset_path, f) for f in os.listdir(dataset_path)]
    face_samples = []
    ids = []

    for image_path in image_paths:
        PIL_img = Image.open(image_path).convert('L')  # Convert to grayscale
        img_numpy = np.array(PIL_img, 'uint8')
        user_id = int(os.path.split(image_path)[-1].split(".")[1])
        faces = face_cascade.detectMultiScale(img_numpy)

        for (x, y, w, h) in faces:
            face_samples.append(img_numpy[y:y+h, x:x+w])
            ids.append(user_id)

    recognizer.train(face_samples, np.array(ids))
    recognizer.write(trainer_path)
    print(f"\n[INFO] {len(np.unique(ids))} faces trained. Model saved.")

# real-time
def recognize_faces():
    recognizer.read(trainer_path)
    font = cv2.FONT_HERSHEY_SIMPLEX
    cam = cv2.VideoCapture(2)

    while True:
        ret, img = cam.read()
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(gray, 1.2, 5)

        for (x, y, w, h) in faces:
            cv2.rectangle(img, (x, y), (x + w, y + h), (0, 255, 0), 2)
            user_id, confidence = recognizer.predict(gray[y:y+h, x:x+w])

            if confidence < 100:
                confidence_text = f"{round(100 - confidence)}%"
                if (user_id == 1):
                    name = "Mason"
                elif (user_id == 2):
                    name = "Placeholder"
                
                cv2.putText(img, f"{name}", (x+5, y-5), font, 1, (255, 255, 255), 2)
                cv2.putText(img, confidence_text, (x+5, y+h-5), font, 1, (255, 255, 0), 1)
            else:
                cv2.putText(img, "Unknown", (x+5, y-5), font, 1, (255, 255, 255), 2)

        cv2.imshow('Recognizing Faces', img)

        if cv2.waitKey(10) & 0xFF == ord('q'):
            break

    cam.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    while True:
        print("\n1. Capture Face Data")
        print("2. Train Face Recognizer")
        print("3. Recognize Faces in Real-Time")
        print("4. Exit")

        choice = input("Enter your choice: ")

        if choice == '1':
            user_id = input("Enter User ID for the face data: ")
            capture_faces(user_id)
        elif choice == '2':
            train_recognizer()
        elif choice == '3':
            recognize_faces()
        elif choice == '4':
            break
        else:
            print("[ERROR] Invalid option, try again.")
            
def recognize_face_in_image(image):
    recognizer.read(trainer_path)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = face_cascade.detectMultiScale(gray, 1.2, 5)
    font = cv2.FONT_HERSHEY_SIMPLEX

    for (x, y, w, h) in faces:
        cv2.rectangle(image, (x, y), (x + w, y + h), (0, 255, 0), 2)
        user_id, confidence = recognizer.predict(gray[y:y+h, x:x+w])

        if confidence < 100:
            confidence_text = f"{round(100 - confidence)}%"
            name = "Unknown"

            if user_id == 1:
                name = "Mason"
            elif user_id == 2:
                name = "Max"

            cv2.putText(image, f"{name}", (x+5, y-5), font, 1, (255, 255, 255), 2)
            cv2.putText(image, confidence_text, (x+5, y+h-5), font, 1, (255, 255, 0), 1)
        else:
            cv2.putText(image, "Unknown", (x+5, y-5), font, 1, (255, 255, 255), 2)

    return image