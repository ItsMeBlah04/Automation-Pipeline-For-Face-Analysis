from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

import cv2
import numpy as np
import onnxruntime as ort


@dataclass
class Detection:
    box: Tuple[int, int, int, int]
    score: float
    keypoints: List[Tuple[int, int]]


class FaceDetection:
    DEFAULT_MODEL_PATH = Path(__file__).resolve().parents[2] / "weights" / "blazeface_fp32.onnx"
    DEFAULT_ANCHORS_PATH = Path(__file__).resolve().parent.parent / "utils" / "anchors.npy"

    def __init__(
        self,
        model_path: Path | None = None,
        anchors_path: Path | None = None,
        *,
        back_model: bool = False,
        providers: Sequence[str] | None = None,
    ):
        self.model_path = Path(model_path) if model_path is not None else self.DEFAULT_MODEL_PATH
        self.anchors_path = Path(anchors_path) if anchors_path is not None else self.DEFAULT_ANCHORS_PATH

        if providers is None:
            providers = ("CPUExecutionProvider",)
        self.session = ort.InferenceSession(str(self.model_path), providers=list(providers))
        self.input_name = self.session.get_inputs()[0].name

        self.anchors = np.load(self.anchors_path).astype(np.float32)
        if self.anchors.shape != (896, 4):
            raise ValueError(f"Unexpected anchors shape {self.anchors.shape}")

        if back_model:
            self.image_size = 256
            self.x_scale = 256.0
            self.y_scale = 256.0
            self.w_scale = 256.0
            self.h_scale = 256.0
            self.min_score_thresh = 0.65
        else:
            self.image_size = 128
            self.x_scale = 128.0
            self.y_scale = 128.0
            self.w_scale = 128.0
            self.h_scale = 128.0
            self.min_score_thresh = 0.25

        self.score_clipping_thresh = 100.0
        self.min_suppression_threshold = 0.3

    @staticmethod
    def _sigmoid(x: np.ndarray) -> np.ndarray:
        return 1.0 / (1.0 + np.exp(-x))

    @staticmethod
    def _intersect(box_a: np.ndarray, box_b: np.ndarray) -> np.ndarray:
        max_xy = np.minimum(box_a[None, 2:], box_b[:, 2:])
        min_xy = np.maximum(box_a[None, :2], box_b[:, :2])
        inter = np.clip(max_xy - min_xy, a_min=0.0, a_max=None)
        return inter[:, 0] * inter[:, 1]

    @classmethod
    def _jaccard(cls, box_a: np.ndarray, box_b: np.ndarray) -> np.ndarray:
        inter = cls._intersect(box_a, box_b)
        area_a = (box_a[2] - box_a[0]) * (box_a[3] - box_a[1])
        area_b = (box_b[:, 2] - box_b[:, 0]) * (box_b[:, 3] - box_b[:, 1])
        union = area_a + area_b - inter
        return inter / np.clip(union, a_min=1e-6, a_max=None)

    @classmethod
    def _weighted_non_max_suppression(
        cls, detections: np.ndarray, min_suppression_threshold: float
    ) -> List[np.ndarray]:
        if detections.size == 0:
            return []

        output: List[np.ndarray] = []
        remaining = np.argsort(detections[:, 16])[::-1]

        while remaining.size > 0:
            detection = detections[remaining[0]]
            other_boxes = detections[remaining, :4]
            ious = cls._jaccard(detection[:4], other_boxes)

            mask = ious > min_suppression_threshold
            overlapping = remaining[mask]
            remaining = remaining[~mask]

            weighted_detection = detection.copy()
            if overlapping.size > 1:
                coordinates = detections[overlapping, :16]
                scores = detections[overlapping, 16:17]
                total_score = np.sum(scores)
                weighted = np.sum(coordinates * scores, axis=0) / total_score
                weighted_detection[:16] = weighted
                weighted_detection[16] = total_score / overlapping.size

            output.append(weighted_detection)

        return output

    def _decode_boxes(
        self,
        raw_boxes: np.ndarray,
    ) -> np.ndarray:
        boxes = np.zeros_like(raw_boxes, dtype=np.float32)

        x_center = raw_boxes[:, 0] / self.x_scale * self.anchors[:, 2] + self.anchors[:, 0]
        y_center = raw_boxes[:, 1] / self.y_scale * self.anchors[:, 3] + self.anchors[:, 1]

        w = raw_boxes[:, 2] / self.w_scale * self.anchors[:, 2]
        h = raw_boxes[:, 3] / self.h_scale * self.anchors[:, 3]

        boxes[:, 0] = y_center - h / 2.0  # ymin
        boxes[:, 1] = x_center - w / 2.0  # xmin
        boxes[:, 2] = y_center + h / 2.0  # ymax
        boxes[:, 3] = x_center + w / 2.0  # xmax

        for k in range(6):
            offset = 4 + k * 2
            keypoint_x = raw_boxes[:, offset] / self.x_scale * self.anchors[:, 2] + self.anchors[:, 0]
            keypoint_y = raw_boxes[:, offset + 1] / self.y_scale * self.anchors[:, 3] + self.anchors[:, 1]
            boxes[:, offset] = keypoint_x
            boxes[:, offset + 1] = keypoint_y

        return boxes

    def _preprocess(self, frame_bgr: np.ndarray) -> np.ndarray:
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        resized = cv2.resize(frame_rgb, (self.image_size, self.image_size))
        normalized = resized.astype(np.float32) / 127.5 - 1.0
        tensor = np.transpose(normalized, (2, 0, 1))[None, ...]
        return tensor

    def _infer(self, input_tensor: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        outputs = self.session.run(None, {self.input_name: input_tensor})
        first, second = outputs
        if first.shape[-1] == 16:
            raw_boxes, raw_scores = first, second
        else:
            raw_scores, raw_boxes = first, second
        return raw_boxes.squeeze(0), raw_scores.squeeze(0)

    def _postprocess(
        self,
        raw_boxes: np.ndarray,
        raw_scores: np.ndarray,
        *,
        min_score_thresh: float,
        nms_threshold: float,
    ) -> List[np.ndarray]:
        if raw_scores.ndim == 2 and raw_scores.shape[1] == 1:
            raw_scores = raw_scores.reshape(-1)

        raw_scores = np.clip(raw_scores, -self.score_clipping_thresh, self.score_clipping_thresh)
        detection_scores = self._sigmoid(raw_scores)
        mask = detection_scores >= min_score_thresh

        decoded_boxes = self._decode_boxes(raw_boxes)

        boxes = decoded_boxes[mask]
        scores = detection_scores[mask]
        if boxes.size == 0:
            return []

        detections = np.concatenate([boxes, scores[:, None]], axis=1)
        return self._weighted_non_max_suppression(detections, nms_threshold)

    def detect(
        self,
        frame_bgr: np.ndarray,
        *,
        score_threshold: float | None = None,
        nms_threshold: float | None = None,
    ) -> List[Detection]:
        score_thresh = score_threshold if score_threshold is not None else self.min_score_thresh
        nms_thresh = nms_threshold if nms_threshold is not None else self.min_suppression_threshold

        input_tensor = self._preprocess(frame_bgr)
        raw_boxes, raw_scores = self._infer(input_tensor)
        detections = self._postprocess(
            raw_boxes,
            raw_scores,
            min_score_thresh=score_thresh,
            nms_threshold=nms_thresh,
        )

        height, width = frame_bgr.shape[:2]
        debug_index = 0
        results: List[Detection] = []
        for detection in detections:
            ymin, xmin, ymax, xmax = detection[:4]
            xmin = int(np.clip(xmin * width, 0, width - 1))
            xmax = int(np.clip(xmax * width, 0, width - 1))
            ymin = int(np.clip(ymin * height, 0, height - 1))
            ymax = int(np.clip(ymax * height, 0, height - 1))

            keypoints: List[Tuple[int, int]] = []
            tight_points: List[Tuple[int, int]] = []
            for k in range(6):
                kp_x = detection[4 + k * 2]
                kp_y = detection[5 + k * 2]
                kp_px = int(np.clip(kp_x * width, 0, width - 1))
                kp_py = int(np.clip(kp_y * height, 0, height - 1))
                keypoints.append((kp_px, kp_py))
                tight_points.append((kp_px, kp_py))

            if len(tight_points) >= 6:
                left_anchor = tight_points[4]
                right_anchor = tight_points[5]
                eye_left = tight_points[0]
                eye_right = tight_points[1]

                anchor_width = max(float(right_anchor[0] - left_anchor[0]), 1.0)
                eye_width = max(float(eye_right[0] - eye_left[0]), 1.0)
                left_gap = abs(left_anchor[0] - eye_left[0])
                right_gap = abs(right_anchor[0] - eye_right[0])

                highly_tilted = False
                if right_gap > 0 and left_gap > 0:
                    if left_gap > right_gap * 2.0 or right_gap > left_gap * 2.0:
                        highly_tilted = True

                print("left_gap:", left_gap, "right_gap:", right_gap, "highly_tilted:", highly_tilted)

                if highly_tilted:
                    box = (xmin, ymin, xmax, ymax)
                else:
                    anchor_center_x = (left_anchor[0] + right_anchor[0]) / 2.0
                    shrink_factor = 0.95  # keep ears just outside the tightened box
                    half_width = max(anchor_width * shrink_factor * 0.5, 1.0)
                    base_xmin = anchor_center_x - half_width
                    base_xmax = anchor_center_x + half_width

                    nose_x = float(tight_points[2][0])
                    width_span = max(base_xmax - base_xmin, 1.0)
                    centered_xmin = nose_x - width_span / 2.0
                    centered_xmax = nose_x + width_span / 2.0

                    centered_xmin = max(centered_xmin, 0.0)
                    centered_xmax = min(centered_xmax, float(width - 1))
                    span = centered_xmax - centered_xmin
                    if span < width_span:
                        deficit = width_span - span
                        centered_xmin = max(centered_xmin - deficit / 2.0, 0.0)
                        centered_xmax = min(centered_xmax + deficit / 2.0, float(width - 1))

                    xmin_int = int(round(centered_xmin))
                    xmax_int = int(round(centered_xmax))
                    xmin_int = max(xmin_int, 0)
                    xmax_int = max(xmax_int, xmin_int + 1)
                    xmax_int = min(xmax_int, width - 1)
                    xmin_int = min(xmin_int, xmax_int - 1)

                    box = (xmin_int, ymin, xmax_int, ymax)
            else:
                box = (xmin, ymin, xmax, ymax)

            score = float(detection[16])
            results.append(Detection(box=box, score=score, keypoints=keypoints))

            # debug prints
            # debug_frame = frame_bgr.copy()
            # cv2.rectangle(debug_frame, (box[0], box[1]), (box[2], box[3]), (0, 255, 0), 2)
            # for kp in keypoints:
            #     cv2.circle(debug_frame, kp, 2, (0, 0, 255), -1)

            # cv2.imwrite(f"debug_detection_{debug_index}.jpg", debug_frame)
            # debug_index += 1

        return results

    def detect_batch(
        self,
        frames: Iterable[np.ndarray],
        *,
        score_threshold: float | None = None,
        nms_threshold: float | None = None,
    ) -> List[List[Detection]]:
        return [
            self.detect(frame, score_threshold=score_threshold, nms_threshold=nms_threshold)
            for frame in frames
        ]

    @classmethod
    def from_default_paths(
        cls,
        *,
        model_path: Path | None = None,
        anchors_path: Path | None = None,
        back_model: bool = False,
        providers: Sequence[str] | None = None,
    ) -> "FaceDetection":
        model = Path(model_path) if model_path is not None else cls.DEFAULT_MODEL_PATH
        anchors = Path(anchors_path) if anchors_path is not None else cls.DEFAULT_ANCHORS_PATH
        return cls(model_path=model, anchors_path=anchors, back_model=back_model, providers=providers)
