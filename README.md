# Presentation
# Automation Pipeline for Face Analysis

A fully automated CI/CD pipeline for a face analysis web application that detects faces, estimates gender and age, and analyzes emotions from uploaded images or webcam captures.

## 🚀 Features

- **Face Detection**: Detects multiple faces in images using BlazeFace
- **Gender & Age Estimation**: Predicts gender and age ranges for detected faces
- **Emotion Analysis**: Analyzes facial expressions and emotions
- **Webcam Support**: Capture images directly from your webcam
- **Modern UI**: React-based frontend with drag-and-drop image upload

## 🏗️ Architecture

### Backend (FastAPI)
- **Location**: `backend/`
- **Framework**: FastAPI with Python 3.11
- **Port**: 8000
- **Features**:
  - `/analyze` - Upload and analyze images
  - `/health` - Health check endpoint
  - `/docs` - Interactive API documentation

### Frontend (React)
- **Location**: `frontend/`
- **Framework**: React 18 with Vite
- **Port**: 5173 (dev) / 80 (production)
- **Features**:
  - Image upload with drag-and-drop
  - Webcam capture
  - Real-time face analysis visualization
  - Responsive design

## 🛠️ Tech Stack

- **Backend**: FastAPI, ONNX Runtime, OpenCV, NumPy
- **Frontend**: React, Vite
- **Infrastructure**: Docker, Docker Compose
- **CI/CD**: Jenkins
- **Cloud**: AWS (EC2, ECR, CloudWatch)
- **Version Control**: GitHub

## 📦 Deployment

The application is deployed using a fully automated CI/CD pipeline:

1. **Source**: GitHub repository
2. **Build**: Jenkins builds Docker images
3. **Test**: Automated smoke tests
4. **Registry**: AWS ECR for Docker images
5. **Deploy**: AWS EC2 instances
6. **Monitor**: AWS CloudWatch

### Environments

- **Staging**: `ec2-54-79-229-133.ap-southeast-2.compute.amazonaws.com`
- **Production**: `ec2-13-54-122-153.ap-southeast-2.compute.amazonaws.com`

## 🚦 CI/CD Pipeline

The Jenkins pipeline includes:
- ✅ Automated build and test
- ✅ Docker image creation and push to ECR
- ✅ Deployment to staging (automatic)
- ✅ Manual approval for production
- ✅ Smoke tests after deployment
- ✅ Automatic rollback on failure

## 📝 Local Development

### Prerequisites
- Docker and Docker Compose
- Node.js 20+ (for frontend development)
- Python 3.11+ (for backend development)

### Running Locally

1. **Using Docker Compose**:
```bash
docker-compose up
```

2. **Access the application**:
- Frontend: http://localhost:5173
- Backend API: http://localhost:8000
- API Docs: http://localhost:8000/docs

### Manual Setup

**Backend**:
```bash
cd backend
pip install -r requirements.txt
uvicorn service_api:app --reload
```

**Frontend**:
```bash
cd frontend
npm install
npm run dev
```

## 📊 Project Structure

```
.
├── backend/              # FastAPI backend service
│   ├── Services/        # Face analysis services
│   ├── weights/         # ONNX model weights
│   └── service_api.py   # Main API application
├── frontend/            # React frontend application
│   ├── src/
│   │   ├── components/  # React components
│   │   └── api/         # API client
│   └── package.json
├── infra/               # Infrastructure configuration
│   ├── deploy/          # Deployment scripts
│   └── cloudwatch/      # CloudWatch configuration
├── Jenkinsfile          # CI/CD pipeline definition
└── docker-compose.yml   # Local development setup
```

## 🧪 Testing

Run smoke tests after deployment:
```bash
./infra/deploy/smoke_test.sh [staging|prod] <EC2_HOST>
```

## 📄 License

University Software Deployment and Evolution Project

## 👥 Authors

Automated CI/CD Pipeline with Docker, Jenkins, AWS & CloudWatch
