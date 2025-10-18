import { useEffect, useRef } from "react";

function drawFace(ctx, face) {
  const bbox = face.bbox ?? {};
  const x = bbox.xmin ?? 0;
  const y = bbox.ymin ?? 0;
  const width = (bbox.xmax ?? x) - x;
  const height = (bbox.ymax ?? y) - y;
  if (width <= 0 || height <= 0) {
    return;
  }

  ctx.strokeStyle = "#2563eb";
  ctx.lineWidth = 2;
  ctx.strokeRect(x, y, width, height);

  const tagParts = [];
  if (face.emotion?.label) {
    const conf = face.emotion?.confidence != null
      ? ` ${(face.emotion.confidence * 100).toFixed(1)}%`
      : "";
    tagParts.push(`${face.emotion.label}${conf}`);
  }
  if (face.gender) tagParts.push(face.gender);
  if (face.age_bucket) tagParts.push(face.age_bucket);

  if (tagParts.length > 0) {
    const tag = tagParts.join(" | ");
    const pad = 4;
    const textWidth = ctx.measureText(tag).width + pad * 2;
    ctx.fillStyle = "rgba(37,99,235,0.85)";
    ctx.fillRect(x, y - 22, textWidth, 20);
    ctx.fillStyle = "#fff";
    ctx.fillText(tag, x + pad, y - 7);
  }

  if (Array.isArray(face.keypoints)) {
    ctx.fillStyle = "#fbbf24";
    face.keypoints.forEach((kp) => {
      if (kp && typeof kp.x === "number" && typeof kp.y === "number") {
        ctx.beginPath();
        ctx.arc(kp.x, kp.y, 2.5, 0, Math.PI * 2);
        ctx.fill();
      }
    });
  }
}

export default function PreviewCanvas({ imageUrl, results }) {
  const canvasRef = useRef(null);

  useEffect(() => {
    if (!imageUrl) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const img = new Image();
    img.onload = () => {
      canvas.width = img.width;
      canvas.height = img.height;
      ctx.drawImage(img, 0, 0);
      ctx.font = "14px system-ui";
      if (!results?.faces) return;
      results.faces.forEach((face) => drawFace(ctx, face));
    };
    img.src = imageUrl;
  }, [imageUrl, results]);

  return <canvas ref={canvasRef} />;
}
