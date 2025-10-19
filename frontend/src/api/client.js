const FALLBACK_URL = typeof window !== "undefined"
  ? `${window.location.protocol}//${window.location.host}`
  : "http://127.0.0.1:8000";

const API_URL = import.meta.env.VITE_API_URL ?? FALLBACK_URL;

export async function analyzeImage(file) {
  const formData = new FormData();
  formData.append("image", file);

  const response = await fetch(`${API_URL}/analyze`, {
    method: "POST",
    body: formData,
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || "Face analysis request failed");
  }

  return response.json();
}
