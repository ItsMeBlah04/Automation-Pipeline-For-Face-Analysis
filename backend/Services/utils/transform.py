from __future__ import annotations

from typing import Sequence, Tuple

import cv2
import numpy as np
from skimage import transform as sk_transform


def gender_age_transform(
    frame: np.ndarray,
    center: Tuple[float, float],
    output_size: int,
    scale: float,
    rotation: float,
) -> Tuple[np.ndarray, np.ndarray]:
    """Mimic InsightFace face_align.transform for gender/age inputs."""
    rot = float(rotation) * np.pi / 180.0
    transform_scale = sk_transform.SimilarityTransform(scale=scale)
    cx = center[0] * scale
    cy = center[1] * scale
    transform_translate = sk_transform.SimilarityTransform(translation=(-1*cx, -1*cy))
    transform_rotate = sk_transform.SimilarityTransform(rotation=rot)
    transform_center = sk_transform.SimilarityTransform(
        translation=(output_size / 2.0, output_size / 2.0)
    )

    transform = transform_scale + transform_translate + transform_rotate + transform_center
    matrix = transform.params[0:2]
    cropped = cv2.warpAffine(
        frame,
        matrix,
        (output_size, output_size),
        borderValue=0.0,
    )
    return cropped, matrix


def emotion_face_align(
    frame: np.ndarray,
    bbox: Sequence[float],
    keypoints: Sequence[Tuple[float, float]] | None,
    *,
    output_size: int,
    margin: float = 1.25,
) -> np.ndarray:
    """Align a face for emotion recognition using BlazeFace eye landmarks."""
    frame_h, frame_w = frame.shape[:2]
    x1, y1, x2, y2 = [float(v) for v in bbox]
    width = max(x2 - x1, 1.0)
    height = max(y2 - y1, 1.0)

    if keypoints and len(keypoints) >= 2:
        eyes = np.array(keypoints[:2], dtype=np.float32)
        order = np.argsort(eyes[:, 0])
        left_eye = eyes[order[0]]
        right_eye = eyes[order[1]]
    else:
        left_eye = np.array([x1 + 0.3 * width, y1 + 0.4 * height], dtype=np.float32)
        right_eye = np.array([x1 + 0.7 * width, y1 + 0.4 * height], dtype=np.float32)

    eyes_center = (left_eye + right_eye) / 2.0
    dx = right_eye[0] - left_eye[0]
    dy = right_eye[1] - left_eye[1]
    angle = np.degrees(np.arctan2(dy, dx)) if np.hypot(dx, dy) > 1e-6 else 0.0
    rotation_center = tuple(eyes_center.tolist())

    rotation_matrix = cv2.getRotationMatrix2D(rotation_center, angle, 1.0)
    rotated = cv2.warpAffine(frame, rotation_matrix, (frame_w, frame_h), flags=cv2.INTER_LINEAR)

    face_center = np.array([(x1 + x2) / 2.0, (y1 + y2) / 2.0, 1.0], dtype=np.float32)
    rotated_center = rotation_matrix @ face_center

    crop_size = max(width, height) * margin
    half = crop_size / 2.0
    rx1 = int(round(rotated_center[0] - half))
    ry1 = int(round(rotated_center[1] - half))
    rx2 = int(round(rotated_center[0] + half))
    ry2 = int(round(rotated_center[1] + half))

    rx1 = max(rx1, 0)
    ry1 = max(ry1, 0)
    rx2 = min(rx2, frame_w)
    ry2 = min(ry2, frame_h)

    if rx2 <= rx1 or ry2 <= ry1:
        rx1 = max(int(round(x1)), 0)
        ry1 = max(int(round(y1)), 0)
        rx2 = min(int(round(x2)), frame_w)
        ry2 = min(int(round(y2)), frame_h)
        rotated = frame

    aligned = rotated[ry1:ry2, rx1:rx2]
    if aligned.size == 0:
        aligned = frame[max(int(y1), 0):min(int(y2), frame_h), max(int(x1), 0):min(int(x2), frame_w)]

    aligned = cv2.resize(aligned, (output_size, output_size), interpolation=cv2.INTER_LINEAR)
    return aligned


def emotion_vectorize_face(
    aligned_faces: Sequence[np.ndarray],
    *,
    output_size: Tuple[int, int],
) -> np.ndarray:
    """Convert aligned emotion faces into model input tensors."""
    tensors = []
    width, height = output_size
    for face in aligned_faces:
        if face.size == 0:
            continue
        gray = cv2.cvtColor(face, cv2.COLOR_BGR2GRAY) if face.ndim == 3 else face
        gray = cv2.resize(gray, (width, height), interpolation=cv2.INTER_LINEAR)
        gray = cv2.equalizeHist(gray)
        normalized = (gray.astype(np.float32) / 255.0)[None, None, :, :]
        tensors.append(normalized)

    if not tensors:
        return np.empty((0, 1, output_size[1], output_size[0]), dtype=np.float32)

    return np.concatenate(tensors, axis=0)
