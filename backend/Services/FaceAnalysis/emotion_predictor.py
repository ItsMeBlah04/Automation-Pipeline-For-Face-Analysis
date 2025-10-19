from __future__ import annotations

from typing import List, Sequence, Tuple

import numpy as np
import onnxruntime as ort

from Services.utils.transform import emotion_face_align, emotion_vectorize_face


class EmotionPredictor:
    def __init__(self, model_path: str):
        self.session = ort.InferenceSession(model_path)
        input_cfg = self.session.get_inputs()[0]
        self.input_name = input_cfg.name
        channels = input_cfg.shape[1]
        height = input_cfg.shape[2]
        width = input_cfg.shape[3]
        if not all(isinstance(dim, int) for dim in (channels, height, width)):
            raise ValueError("Emotion model input must have static channel, height, and width.")
        if channels != 1:
            raise ValueError(f"Emotion model expects 1-channel input, got {channels}.")
        self.input_size = (width, height)

        output_cfg = self.session.get_outputs()[0]
        self.output_dim = int(output_cfg.shape[1]) if isinstance(output_cfg.shape[1], int) else None
        self.classes = ["angry", "disgust", "fear", "happy", "sad", "surprise", "neutral"]

    def preprocess(
        self,
        frame: np.ndarray,
        face_bboxes: Sequence[Sequence[float]],
        landmarks: Sequence[Sequence[Tuple[float, float]]],
    ) -> np.ndarray:
        if len(face_bboxes) != len(landmarks):
            raise ValueError("Each face bounding box must have a corresponding landmarks entry.")

        aligned_faces: List[np.ndarray] = []
        target_size = self.input_size[0]
        for bbox, kps in zip(face_bboxes, landmarks):
            aligned = emotion_face_align(
                frame,
                bbox,
                kps,
                output_size=target_size,
            )
            aligned_faces.append(aligned)

        return emotion_vectorize_face(aligned_faces, output_size=self.input_size)

    def inference(self, input_tensor: np.ndarray) -> np.ndarray:
        if input_tensor.size == 0:
            return np.empty((0, self.output_dim or 0), dtype=np.float32)
        outputs = self.session.run(None, {self.input_name: input_tensor})
        return outputs[0]

    def predict(
        self,
        frame: np.ndarray,
        face_bboxes: Sequence[Sequence[float]],
        landmarks: Sequence[Sequence[Tuple[float, float]]],
    ) -> List[Tuple[int, float, np.ndarray]]:
        input_tensor = self.preprocess(frame, face_bboxes, landmarks)
        outputs = self.inference(input_tensor)
        return self.postprocess(outputs)

    def postprocess(self, outputs: np.ndarray) -> List[Tuple[int, float, np.ndarray]]:
        if outputs.size == 0:
            return []

        logits = outputs.astype(np.float32)
        logits -= np.max(logits, axis=1, keepdims=True)
        exp = np.exp(logits)
        probs = exp / np.sum(exp, axis=1, keepdims=True)

        results: List[Tuple[int, float, np.ndarray]] = []
        for probability in probs:
            label = int(np.argmax(probability))
            confidence = float(probability[label])
            if confidence < 0.5:
                emotion_index = -1
            else:
                emotion_index = label
            emotion_label = self.classes[emotion_index]
            results.append((emotion_label, confidence, probability))
        return results
