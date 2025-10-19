# Face Frontend (Demo — Fake Data)
React (Vite) frontend showing upload/camera and visualising placeholder predictions
(emotion, gender, age). No backend/API required yet.

## Run (macOS)
```bash
npm install
npm run dev
```
Open the printed URL (likely http://localhost:5173)

## Where to plug real API later
Edit `src/api/client.js` to call your FastAPI endpoint.
Add `.env` with `VITE_API_BASE_URL=http://54.79.229.133:8000`
