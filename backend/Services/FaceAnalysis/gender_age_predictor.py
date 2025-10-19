from __future__ import annotations

from typing import List, Sequence, Tuple

import cv2
import numpy as np
import onnx
import onnxruntime as ort

from Services.utils.transform import gender_age_transform


class GenderAgePredictor:
    def __init__(self, model_path: str):
        self.session = ort.InferenceSession(model_path)
        input_cfg = self.session.get_inputs()[0]
        self.input_name = input_cfg.name
        self.input_shape = input_cfg.shape
        height, width = input_cfg.shape[2], input_cfg.shape[3]
        if not isinstance(height, int) or not isinstance(width, int):
            raise ValueError("Model input height and width must be static integers.")
        self.channels = int(input_cfg.shape[1]) if isinstance(input_cfg.shape[1], int) else 3
        self.input_size = (width, height)
        self.input_mean, self.input_std = self._infer_normalization(model_path)
        output_cfg = self.session.get_outputs()[0]
        self.output_dim = int(output_cfg.shape[1]) if isinstance(output_cfg.shape[1], int) else 3
        self.classes = ["female", "male"]
        self.age_range = ["0-18", "19-36", "37-60", "60+"]

    @staticmethod
    def _infer_normalization(model_path: str) -> Tuple[float, float]:
        model = onnx.load(model_path)
        graph = model.graph
        find_sub = False
        find_mul = False
        for node in graph.node[:8]:
            name = node.name or ""
            if name.startswith(("Sub", "_minus", "bn_data")):
                find_sub = True
            if name.startswith(("Mul", "_mul", "bn_data")):
                find_mul = True
        if find_sub and find_mul:
            return 0.0, 1.0
        return 127.5, 128.0

    def preprocess(self, frame: np.ndarray, face_bboxes: Sequence[np.ndarray]) -> np.ndarray:
        # if face_bboxes:
        #     x1_dbg, y1_dbg, x2_dbg, y2_dbg = [int(round(v)) for v in face_bboxes[0]]
        #     debug_frame = frame.copy()
        #     cv2.rectangle(debug_frame, (x1_dbg, y1_dbg), (x2_dbg, y2_dbg), (0, 255, 0), 2)
        #     cv2.imwrite("debug_gender_age_frame.jpg", debug_frame)

        blobs: List[np.ndarray] = []
        target_size = self.input_size[0]
        for bbox in face_bboxes:
            x1, y1, x2, y2 = [int(round(v)) for v in bbox]
            width = max(x2 - x1, 1)
            height = max(y2 - y1, 1)
            center = ((x1 + x2) / 2.0, (y1 + y2) / 2.0)
            scale = target_size / (max(width, height) * 1.0)
            cropped, _ = gender_age_transform(frame, center, target_size, scale, 0.0)
            # debug cropped
            # cv2.imwrite("debug_gender_age_cropped.jpg", cropped)
            blob = cv2.dnn.blobFromImage(
                cropped,
                scalefactor=1.0 / self.input_std,
                size=self.input_size,
                mean=(self.input_mean, self.input_mean, self.input_mean),
                swapRB=True,
            )
            blobs.append(blob)

        if not blobs:
            return np.empty((0, self.channels, self.input_size[1], self.input_size[0]), dtype=np.float32)

        return np.concatenate(blobs, axis=0)

    def inference(self, input_tensor: np.ndarray) -> np.ndarray:
        if input_tensor.size == 0:
            return np.empty((0, self.output_dim), dtype=np.float32)
        outputs = self.session.run(None, {self.input_name: input_tensor})
        return outputs[0]

    def predict(self, frame: np.ndarray, face_bboxes: Sequence[np.ndarray]) -> List[Tuple[int, int]]:
        input_tensor = self.preprocess(frame, face_bboxes)
        outputs = self.inference(input_tensor)
        return self.postprocess(outputs)

    def _age_label(self, age_value: int) -> str:
        if age_value <= 18:
            return self.age_range[0]
        if age_value <= 36:
            return self.age_range[1]
        if age_value <= 60:
            return self.age_range[2]
        return self.age_range[3]

    def postprocess(self, outputs: np.ndarray) -> List[Tuple[str, str]]:
        results: List[Tuple[str, str]] = []
        for pred in outputs:
            gender = int(np.argmax(pred[:2]))
            gender_label = self.classes[gender]
            age = int(np.round(pred[2] * 100))
            age_bucket = self._age_label(age)
            results.append((gender_label, age_bucket))
        return results
