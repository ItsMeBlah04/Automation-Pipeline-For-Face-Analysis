from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np

from Services.FaceDetection.inference import FaceDetection as BlazeFaceDetector
from Services.FaceAnalysis.gender_age_predictor import GenderAgePredictor
from Services.FaceAnalysis.emotion_predictor import EmotionPredictor


WEIGHTS_DIR = Path(__file__).resolve().parent / "weights"


@dataclass
class AggregatedFaceResult:
    bbox: Tuple[int, int, int, int]
    score: float
    keypoints: List[Tuple[int, int]]
    gender: Optional[str]
    age_bucket: Optional[str]
    emotion_label: Optional[str | int]
    emotion_confidence: Optional[float]
    emotion_distribution: Optional[List[float]]

    def as_dict(self) -> Dict[str, Any]:
        return {
            "bbox": {
                "xmin": self.bbox[0],
                "ymin": self.bbox[1],
                "xmax": self.bbox[2],
                "ymax": self.bbox[3],
            },
            "score": self.score,
            "keypoints": [{"x": kp[0], "y": kp[1]} for kp in self.keypoints],
            "gender": self.gender,
            "age_bucket": self.age_bucket,
            "emotion": {
                "label": self.emotion_label,
                "confidence": self.emotion_confidence,
                "distribution": self.emotion_distribution,
            }
            if self.emotion_label is not None
            else None,
        }


class StreamingFaceAnalysis:
    def __init__(
        self,
        *,
        face_model_path: Optional[Path] = None,
        face_anchors_path: Optional[Path] = None,
        gender_age_model_path: Optional[Path] = None,
        emotion_model_path: Optional[Path] = None,
        back_model: bool = False,
        emotion_labels: Optional[Sequence[str]] = None,
    ):
        self.detector = BlazeFaceDetector.from_default_paths(
            model_path=face_model_path,
            anchors_path=face_anchors_path,
            back_model=back_model,
        )

        if gender_age_model_path is None:
            gender_age_model_path = WEIGHTS_DIR / "genderage.onnx"
        if not gender_age_model_path.exists():
            raise FileNotFoundError(f"Gender/Age model not found at {gender_age_model_path}")
        self.gender_age = GenderAgePredictor(str(gender_age_model_path))

        if emotion_model_path is None:
            emotion_model_path = WEIGHTS_DIR / "mini_xception_fp32.onnx"
        if not emotion_model_path.exists():
            raise FileNotFoundError(f"Emotion model not found at {emotion_model_path}")
        self.emotion = EmotionPredictor(str(emotion_model_path))

        self.emotion_labels = list(emotion_labels) if emotion_labels is not None else None

    def analyze(
        self,
        frame: np.ndarray,
        *,
        score_threshold: Optional[float] = None,
        nms_threshold: Optional[float] = None,
    ) -> Dict[str, Any]:
        detections = self.detector.detect(
            frame,
            score_threshold=score_threshold,
            nms_threshold=nms_threshold,
        )
        if not detections:
            return {"faces": []}

        face_bboxes = [np.array(det.box, dtype=np.float32) for det in detections]
        landmarks = [det.keypoints for det in detections]

        gender_age_results = self.gender_age.predict(frame, face_bboxes)
        emotion_results = self.emotion.predict(frame, face_bboxes, landmarks)

        aggregated: List[AggregatedFaceResult] = []
        for idx, det in enumerate(detections):
            gender: Optional[str] = None
            age_bucket: Optional[str] = None
            if idx < len(gender_age_results):
                gender, age_bucket = gender_age_results[idx]

            emotion_label: Optional[int] = None
            emotion_conf: Optional[float] = None
            emotion_dist: Optional[List[float]] = None
            if idx < len(emotion_results):
                label_idx, confidence, distribution = emotion_results[idx]
                emotion_label = (
                    self.emotion_labels[label_idx]
                    if self.emotion_labels is not None and 0 <= label_idx < len(self.emotion_labels)
                    else label_idx
                )
                emotion_conf = confidence
                emotion_dist = distribution.tolist()

            aggregated.append(
                AggregatedFaceResult(
                    bbox=det.box,
                    score=det.score,
                    keypoints=det.keypoints,
                    gender=gender,
                    age_bucket=age_bucket,
                    emotion_label=emotion_label,
                    emotion_confidence=emotion_conf,
                    emotion_distribution=emotion_dist,
                )
            )

        return {"faces": [face.as_dict() for face in aggregated]}


__all__ = ["StreamingFaceAnalysis"]
