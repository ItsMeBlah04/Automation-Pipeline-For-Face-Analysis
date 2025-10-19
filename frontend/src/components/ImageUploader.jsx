import { useEffect, useRef, useState } from "react";

export default function ImageUploader({ onSelected }) {
  const inputRef = useRef(null);
  const [preview, setPreview] = useState(null);

  function setFile(file) {
    if (!file) return;
    if (preview) URL.revokeObjectURL(preview);
    const url = URL.createObjectURL(file);
    setPreview(url);
    if (inputRef.current) {
      inputRef.current.value = "";
    }
    onSelected?.(file, url);
  }

  useEffect(() => {
    return () => {
      if (preview) {
        URL.revokeObjectURL(preview);
      }
    };
  }, [preview]);

  function handleChange(event) {
    const file = event.target.files?.[0];
    if (file) setFile(file);
  }

  function handleDrop(event) {
    event.preventDefault();
    const file = event.dataTransfer.files?.[0];
    if (file) setFile(file);
  }

  function handleKeyDown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      inputRef.current?.click();
    }
  }

  function clearPreview() {
    if (preview) {
      URL.revokeObjectURL(preview);
    }
    setPreview(null);
    if (inputRef.current) {
      inputRef.current.value = "";
    }
  }

  return (
    <div className="uploader">
      <div
        className={`dropzone ${preview ? "dropzone--preview" : ""}`}
        onDragOver={(e) => e.preventDefault()}
        onDrop={handleDrop}
        onClick={() => inputRef.current?.click()}
        onKeyDown={handleKeyDown}
        tabIndex={0}
        role="button"
        aria-label="Upload an image"
      >
        {preview ? (
          <img src={preview} alt="Selected preview" />
        ) : (
          <div className="dropzone__placeholder">
            <span className="dropzone__icon" aria-hidden="true">??</span>
            <p>Drag &amp; drop an image, or click to browse.</p>
            <span className="dropzone__hint">JPG, PNG or WEBP up to ~10MB.</span>
          </div>
        )}
      </div>

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        hidden
        onChange={handleChange}
      />

      <div className="button-row">
        <button type="button" className="btn primary" onClick={() => inputRef.current?.click()}>
          Browse files
        </button>
        {preview && (
          <button type="button" className="btn ghost" onClick={clearPreview}>
            Clear selection
          </button>
        )}
      </div>

      <p className="muted small">
        Files are previewed locally first. We only send the selected image when you request analysis.
      </p>
    </div>
  );
}
