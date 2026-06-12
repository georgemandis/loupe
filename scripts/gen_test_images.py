#!/usr/bin/env python3
"""Generate ArUco test fixtures into testdata/.

Usage:
    uv run --with opencv-python-headless scripts/gen_test_images.py
"""
import os
import sys

try:
    import cv2
    import numpy as np
except ImportError:
    sys.exit("opencv-python-headless and numpy required. Run: uv run --with opencv-python-headless --with numpy scripts/gen_test_images.py")

os.makedirs("testdata", exist_ok=True)

d4 = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
d6 = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_6X6_250)

# Plain 4x4 marker, id 23
canvas = np.full((400, 400), 255, np.uint8)
canvas[80:320, 80:320] = cv2.aruco.generateImageMarker(d4, 23, 240)
cv2.imwrite("testdata/aruco_4x4_23.png", canvas)

# 6x6 marker, id 42, rotated 25 degrees
canvas = np.full((480, 480), 255, np.uint8)
canvas[120:360, 120:360] = cv2.aruco.generateImageMarker(d6, 42, 240)
rot = cv2.getRotationMatrix2D((240, 240), 25, 1.0)
rotated = cv2.warpAffine(canvas, rot, (480, 480), borderValue=255, flags=cv2.INTER_LINEAR)
cv2.imwrite("testdata/aruco_6x6_42_rot25.png", rotated)

# Two markers from different families in one image
canvas = np.full((400, 800), 255, np.uint8)
canvas[100:300, 60:260] = cv2.aruco.generateImageMarker(d4, 7, 200)
canvas[100:300, 540:740] = cv2.aruco.generateImageMarker(d6, 42, 200)
cv2.imwrite("testdata/aruco_multi.png", canvas)

print("wrote 3 fixtures to testdata/")
