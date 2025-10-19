from __future__ import annotations

from typing import Optional

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from StreamingFaceAnalysis import StreamingFaceAnalysis


app = FastAPI(
    title="Automation Pipeline Face Analysis API",
    description="Detect faces and run gender/age/emotion inference on uploaded images.",
    version="1.0.0",
    docs_url="/docs",
)

_pipeline: Optional[StreamingFaceAnalysis] = None

# Allow local dev frontends by default; override with env if needed.
DEFAULT_ORIGINS = {
    "http://localhost:5173",
    "http://127.0.0.1:5173",
}


app.add_middleware(
    CORSMiddleware,
    allow_origins=list(DEFAULT_ORIGINS),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_pipeline() -> StreamingFaceAnalysis:
    global _pipeline
    if _pipeline is None:
        _pipeline = StreamingFaceAnalysis()
    return _pipeline


@app.on_event("startup")
def _load_models() -> None:
    get_pipeline()


@app.get("/health")
def health() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.post("/analyze")
async def analyze_image(
    image: UploadFile = File(...),
    score_threshold: Optional[float] = Query(
        None,
        ge=0.0,
        le=1.0,
        description="Optional override for detector minimum confidence (0-1).",
    ),
    nms_threshold: Optional[float] = Query(
        None,
        ge=0.0,
        le=1.0,
        description="Optional override for detector NMS IoU threshold.",
    ),
) -> JSONResponse:
    content = await image.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    file_bytes = np.asarray(bytearray(content), dtype=np.uint8)
    frame = cv2.imdecode(file_bytes, cv2.IMREAD_COLOR)
    if frame is None:
        raise HTTPException(status_code=400, detail="Unable to decode image content.")

    pipeline = get_pipeline()
    analysis = pipeline.analyze(
        frame,
        score_threshold=score_threshold,
        nms_threshold=nms_threshold,
    )
    response_payload = {
        "filename": image.filename,
        "face_count": len(analysis["faces"]),
        "faces": analysis["faces"],
    }
    return JSONResponse(response_payload)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "service_api:app",      # or "app:app" if your file is app.py
        host="127.0.0.1",
        port=55000,
        # reload=True,
        # log_level="debug",
        # workers=1,              # keep 1 when reload is True
    )
