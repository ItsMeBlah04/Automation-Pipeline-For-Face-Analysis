import Webcam from "react-webcam";
import { useRef, useState } from "react";

export default function WebcamCapture({ onCapture }) {
  const webcamRef = useRef(null);
  const [shot, setShot] = useState(null);

  async function capture() {
    const screenshot = webcamRef.current?.getScreenshot();
    if (!screenshot) return;

    const response = await fetch(screenshot);
    const blob = await response.blob();
    const file = new File([blob], "capture.jpg", { type: "image/jpeg" });

    setShot(screenshot);
    onCapture?.(file, screenshot);
  }

  function clearShot() {
    setShot(null);
  }

  return (
    <div className="webcam">
      <div className="webcam__feed">
        <Webcam
          ref={webcamRef}
          className="webcam__video"
          screenshotFormat="image/jpeg"
          videoConstraints={{ facingMode: "user" }}
        />
      </div>
      <div className="button-row">
        <button type="button" className="btn primary" onClick={capture}>
          Capture frame
        </button>
        {shot && (
          <button type="button" className="btn ghost" onClick={clearShot}>
            Retake
          </button>
        )}
      </div>
      {shot && (
        <img
          src={shot}
          alt="Captured preview"
          className="webcam__preview"
        />
      )}
      <p className="muted small">
        The live camera feed never leaves your browser until you capture a frame.
      </p>
    </div>
  );
}
