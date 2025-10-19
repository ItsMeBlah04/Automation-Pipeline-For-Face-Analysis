export default function ResultPanel({ data }) {
  if (!data) {
    return (
      <div className="empty-state">
        <p>Upload an image or capture a frame to see insights here.</p>
      </div>
    );
  }

  const faces = data.faces ?? [];
  return (
    <div className="result-panel">
      <div className="result-summary">
        <span className="pill">Faces detected: {faces.length}</span>
        {data.filename && (
          <span className="muted small">Source: {data.filename}</span>
        )}
      </div>

      {faces.length === 0 && (
        <div className="empty-state">
          <p>No faces were found in this image.</p>
        </div>
      )}

      {faces.length > 0 && (
        <div className="result-grid">
          {faces.map((face, idx) => {
            const emotion = face.emotion;
            const emotionLabel = emotion?.label ?? "unknown";
            const emotionConf = emotion?.confidence != null
              ? `${(emotion.confidence * 100).toFixed(1)}%`
              : "n/a";
            const gender = face.gender ?? "unknown";
            const ageBucket = face.age_bucket ?? "unknown";
            const detectionScore = face.score != null
              ? `${(face.score * 100).toFixed(1)}%`
              : "n/a";

            return (
              <div key={idx} className="result-card">
                <div className="result-card__title">
                  <span className="face-index">Face {idx + 1}</span>
                  <span className="muted small">Confidence {detectionScore}</span>
                </div>
                <dl>
                  <div>
                    <dt>Emotion</dt>
                    <dd>
                      {emotionLabel}
                      {emotionConf !== "n/a" && <span className="muted"> ({emotionConf})</span>}
                    </dd>
                  </div>
                  <div>
                    <dt>Gender</dt>
                    <dd>{gender}</dd>
                  </div>
                  <div>
                    <dt>Age range</dt>
                    <dd>{ageBucket}</dd>
                  </div>
                </dl>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
