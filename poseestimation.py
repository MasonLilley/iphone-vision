import cv2
import numpy as np
import os
import time
import urllib.request
import tensorflow as tf

class PoseEstimator:
    def __init__(self, model_type="thunder", enable_gpu=True):
        """
        Initialize lightweight pose estimator using Google's MoveNet
        
        Args:
            model_type: "lightning" (faster) or "thunder" (more accurate)
            enable_gpu: Whether to use GPU acceleration
        """
        self.model_type = model_type
        self.enable_gpu = enable_gpu
        
        # Configure TensorFlow to use GPU
        if enable_gpu:
            # Allow TensorFlow to use GPU memory as needed
            gpus = tf.config.experimental.list_physical_devices('GPU')
            if gpus:
                try:
                    for gpu in gpus:
                        tf.config.experimental.set_memory_growth(gpu, True)
                    print(f"GPU acceleration enabled. Found {len(gpus)} GPU(s).")
                except RuntimeError as e:
                    print(f"Error configuring GPU: {e}")
            else:
                print("No GPU found, falling back to CPU")
        
        # Set model paths
        model_name = f"movenet_{model_type}"
        self.model_path = f"models/{model_name}.tflite"
        
        # Create models directory if it doesn't exist
        os.makedirs("models", exist_ok=True)
        
        # Download model if it doesn't exist
        if not os.path.exists(self.model_path):
            print(f"Downloading {model_name} model...")
            self._download_model()
        
        # Load the TFLite model
        self.interpreter = tf.lite.Interpreter(model_path=self.model_path)
        self.interpreter.allocate_tensors()
        
        # Get model details
        self.input_details = self.interpreter.get_input_details()
        self.output_details = self.interpreter.get_output_details()
        
        # Get input type
        self.input_dtype = self.input_details[0]['dtype']
        print(f"Model expects input of type: {self.input_dtype}")
        
        # Determine input size from model
        self.input_size = self.input_details[0]['shape'][1]  # Should be 192 for lightning, 256 for thunder
        print(f"Model loaded. Input size: {self.input_size}x{self.input_size}")
        
        # Define keypoint names for visualization
        self.keypoint_names = [
            'nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
            'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
            'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
            'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
        ]
        
        # Define connections between keypoints for drawing the skeleton
        self.keypoint_connections = [
            # Face connections
            ('nose', 'left_eye'), ('nose', 'right_eye'),
            ('left_eye', 'left_ear'), ('right_eye', 'right_ear'),
            
            # Upper body connections
            ('left_shoulder', 'right_shoulder'), 
            ('left_shoulder', 'left_elbow'), ('right_shoulder', 'right_elbow'),
            ('left_elbow', 'left_wrist'), ('right_elbow', 'right_wrist'),
            
            # Torso connections
            ('left_shoulder', 'left_hip'), ('right_shoulder', 'right_hip'),
            ('left_hip', 'right_hip'),
            
            # Lower body connections
            ('left_hip', 'left_knee'), ('right_hip', 'right_knee'),
            ('left_knee', 'left_ankle'), ('right_knee', 'right_ankle')
        ]
        
        # Performance tracking
        self.last_inference_time = 0
        self.last_preprocess_time = 0
        self.last_postprocess_time = 0
    
    def _download_model(self):
        """Download the MoveNet model"""
        if self.model_type == "lightning":
            url = "https://tfhub.dev/google/lite-model/movenet/singlepose/lightning/tflite/float16/4?lite-format=tflite"
        else:  # thunder
            url = "https://tfhub.dev/google/lite-model/movenet/singlepose/thunder/tflite/float16/4?lite-format=tflite"
        
        try:
            urllib.request.urlretrieve(url, self.model_path)
            print(f"Downloaded model to {self.model_path}")
        except Exception as e:
            print(f"Failed to download model: {e}")
            raise
    
    def preprocess_image(self, image):
        """Preprocess image for the model"""
        start_time = time.time()
        
        # Save original dimensions
        self.image_height, self.image_width = image.shape[:2]
        
        # Resize and pad the image to keep the aspect ratio
        if self.image_height > self.image_width:
            scale = self.input_size / self.image_height
            new_height = self.input_size
            new_width = int(self.image_width * scale)
        else:
            scale = self.input_size / self.image_width
            new_width = self.input_size
            new_height = int(self.image_height * scale)
            
        # Resize image
        resized_img = cv2.resize(image, (new_width, new_height))
        
        # Create a square black image
        input_img = np.zeros((self.input_size, self.input_size, 3), dtype=np.uint8)
        
        # Place the resized image in the center of the square
        dx = (self.input_size - new_width) // 2
        dy = (self.input_size - new_height) // 2
        input_img[dy:dy+new_height, dx:dx+new_width, :] = resized_img
        
        # Save padding info for later use
        self.padding = (dx, dy, scale)
        
        # Add batch dimension to make a 4D tensor
        input_tensor = np.expand_dims(input_img, axis=0)
        
        self.last_preprocess_time = time.time() - start_time
        return input_tensor
    
    def detect_pose(self, image):
        """Detect pose in the image"""
        if image is None or not isinstance(image, np.ndarray):
            return None
            
        # Preprocess image
        input_tensor = self.preprocess_image(image)
        
        # Set input tensor
        self.interpreter.set_tensor(self.input_details[0]['index'], input_tensor)
        
        # Run inference
        start_time = time.time()
        self.interpreter.invoke()
        self.last_inference_time = time.time() - start_time
        
        # Get the output
        start_time = time.time()
        keypoints_with_scores = self.interpreter.get_tensor(self.output_details[0]['index'])
        
        # Post-process keypoints
        keypoints = []
        
        # MoveNet returns y, x, confidence for each keypoint in normalized coordinates
        for i, keypoint in enumerate(keypoints_with_scores[0, 0]):
            y, x, confidence = keypoint
            
            # Convert normalized coordinates to image coordinates
            dx, dy, scale = self.padding
            x_coord = int(((x * self.input_size) - dx) / scale)
            y_coord = int(((y * self.input_size) - dy) / scale)
            
            # Ensure coordinates are within image bounds
            x_coord = max(0, min(x_coord, self.image_width - 1))
            y_coord = max(0, min(y_coord, self.image_height - 1))
            
            # Store keypoint if confidence is high enough
            if confidence > 0.3:  # Threshold can be adjusted
                keypoints.append((x_coord, y_coord, confidence, self.keypoint_names[i]))
            else:
                keypoints.append(None)
        
        self.last_postprocess_time = time.time() - start_time
        return keypoints
    
    def draw_pose(self, image, keypoints=None, draw_stats=False):
        """Draw pose keypoints and skeleton on the image"""
        if image is None:
            return image
            
        # Make a copy of the input image
        annotated_image = image.copy()
        
        # Detect pose if keypoints not provided
        if keypoints is None:
            keypoints = self.detect_pose(annotated_image)
        
        if keypoints:
            # Create a dictionary mapping keypoint names to their coordinates
            keypoint_dict = {}
            for i, point in enumerate(keypoints):
                if point is not None:
                    x, y, conf, name = point[0], point[1], point[2], point[3]
                    keypoint_dict[name] = (int(x), int(y), conf)
            
            # Draw keypoints
            for name, (x, y, conf) in keypoint_dict.items():
                cv2.circle(annotated_image, (x, y), 6, (0, 255, 0), -1)
                # Optionally display confidence
                # cv2.putText(annotated_image, f"{conf:.2f}", (x+10, y), 
                #            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
            
            # Draw connections
            for connection in self.keypoint_connections:
                start_name, end_name = connection
                if start_name in keypoint_dict and end_name in keypoint_dict:
                    start_point = keypoint_dict[start_name]
                    end_point = keypoint_dict[end_name]
                    
                    # Use color based on part of body
                    if 'shoulder' in start_name or 'shoulder' in end_name:
                        color = (0, 255, 0)  # Green for shoulders/upper body
                    elif 'hip' in start_name or 'hip' in end_name:
                        color = (255, 0, 0)   # Blue for hips/midsection
                    elif 'knee' in start_name or 'ankle' in start_name:
                        color = (0, 0, 255)   # Red for legs/lower body
                    else:
                        color = (255, 255, 0) # Yellow for face/head
                        
                    cv2.line(annotated_image, 
                            (start_point[0], start_point[1]), 
                            (end_point[0], end_point[1]), 
                            color, 2)
        
        # Draw performance stats if requested
        if draw_stats:
            total_time = self.last_preprocess_time + self.last_inference_time + self.last_postprocess_time
            
            cv2.putText(annotated_image, 
                       f"Inference: {self.last_inference_time*1000:.1f}ms", 
                       (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            
            cv2.putText(annotated_image, 
                       f"Total: {total_time*1000:.1f}ms", 
                       (10, 90), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            
            cv2.putText(annotated_image, 
                       f"GPU: {'ON' if self.enable_gpu else 'OFF'}", 
                       (10, 120), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            
            cv2.putText(annotated_image, 
                       f"Model: MoveNet {self.model_type}", 
                       (10, 150), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        
        return annotated_image


# Create a global instance of the pose estimator
_pose_estimator = None

def initialize(model_type="thunder", enable_gpu=True):
    """
    Initialize pose estimator with custom parameters.
    Call this before using drawPose to customize settings.
    
    Args:
        model_type: "lightning" (faster) or "thunder" (more accurate)
        enable_gpu: Whether to use GPU acceleration
    """
    global _pose_estimator
    _pose_estimator = PoseEstimator(
        model_type=model_type,
        enable_gpu=enable_gpu
    )

def drawPose(image, draw_stats=True):
    """
    Detects human poses in the image and draws the pose landmarks.
    
    Args:
        image: Input image (BGR format, as used by OpenCV)
        draw_stats: Whether to display performance statistics
        
    Returns:
        Image with pose landmarks drawn on it
    """
    global _pose_estimator
    
    # Initialize the pose estimator if not already initialized
    if _pose_estimator is None:
        print("Initializing pose estimator with Google's MoveNet Lightning model...")
        initialize(model_type="thunder", enable_gpu=True)
    
    try:
        return _pose_estimator.draw_pose(image, draw_stats=draw_stats)
    except Exception as e:
        print(f"Error in pose estimation: {e}")
        import traceback
        traceback.print_exc()
        return image  # Return original image on error

# Initialize with appropriate settings for Jetson Orin Nano
# Use "lightning" for faster inference, "thunder" for more accuracy
initialize(
    model_type="thunder",  # Lightweight model optimized for speed
    enable_gpu=True          # Enable GPU acceleration
)