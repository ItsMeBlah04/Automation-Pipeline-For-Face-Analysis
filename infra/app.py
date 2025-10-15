"""
Face Analysis Backend API (Hello World Placeholder)
This is a minimal FastAPI application that serves as a placeholder for the actual face analysis backend.
"""

from fastapi import FastAPI
from fastapi.responses import JSONResponse

# Create FastAPI application instance
app = FastAPI(
    title="Face Analysis Backend API",
    description="Placeholder backend for face analysis pipeline",
    version="1.0.0"
)

@app.get("/")
async def root():
    """
    Root endpoint that returns a hello world message.
    This will be replaced with actual face analysis endpoints.
    """
    return JSONResponse(
        status_code=200,
        content={"message": "Hello from backend", "service": "face-analysis-backend"}
    )

@app.get("/health")
async def health_check():
    """
    Health check endpoint for monitoring and load balancer checks.
    """
    return JSONResponse(
        status_code=200,
        content={"status": "healthy", "service": "face-analysis-backend"}
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
