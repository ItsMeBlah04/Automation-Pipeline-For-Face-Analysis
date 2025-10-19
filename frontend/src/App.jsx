import { useState } from "react";
import { analyzeImage } from "./api/client";
import ImageUploader from "./components/ImageUploader.jsx";
import WebcamCapture from "./components/WebcamCapture.jsx";
import PreviewCanvas from "./components/PreviewCanvas.jsx";
import ResultPanel from "./components/ResultPanel.jsx";

export default function App() {
  const [imageUrl, setImageUrl] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [results, setResults] = useState(null);

  async function run(file, preview) {
    setImageUrl(preview);
    setResults(null);
    setError("");
    setLoading(true);
    try {
      const data = await analyzeImage(file);
      setResults(data);
    } catch (err) {
      console.error(err);
      setError("Something went wrong while analyzing the image.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="app-shell">
      <header className="app-header card">
        <p className="eyebrow">Automation Pipeline</p>
        <h1>Face Analysis Studio</h1>
        <p className="muted">
          Upload or capture an image to detect faces, estimate gender and age
          ranges, and understand expressions – powered by our FastAPI backend.
        </p>
      </header>

      <main className="app-main">
        <section className="card step-card">
          <div className="step-header">
            <h2 className="section-title">1. Provide an image</h2>
            <p className="muted">Start by dropping a file or capturing a live frame.</p>
          </div>
          <div className="input-grid">
            <div className="option-panel">
              <h3>Upload from your device</h3>
              <p className="muted small">
                Supports JPG, PNG or WEBP. Drag &amp; drop or browse your files.
              </p>
              <ImageUploader onSelected={run} />
            </div>
            <div className="option-panel">
              <h3>Use your camera</h3>
              <p className="muted small">
                Capture a snapshot directly in the browser – nothing is sent
                until you capture.
              </p>
              <WebcamCapture onCapture={run} />
            </div>
          </div>
        </section>

        {loading && (
          <div className="status-banner" role="status">
            <span className="spinner" aria-hidden="true" />
            Analyzing… hang tight.
          </div>
        )}
        {error && (
          <div className="status-banner status-banner--error" role="alert">
            {error}
          </div>
        )}

        {imageUrl && (
          <section className="card preview-card">
            <div className="preview-header">
              <h2 className="section-title">2. Preview &amp; detections</h2>
              {results?.filename && (
                <span className="muted small">
                  Source file: <strong>{results.filename}</strong>
                </span>
              )}
            </div>
            <PreviewCanvas imageUrl={imageUrl} results={results} />
          </section>
        )}

        <section className="card results-card">
          <h2 className="section-title">3. Insights</h2>
          <ResultPanel data={results} />
        </section>
      </main>
    </div>
  );
}
