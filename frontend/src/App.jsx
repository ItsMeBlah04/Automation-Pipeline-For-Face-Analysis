import { useState } from 'react'
import { analyzeImage } from './api/client'
import ImageUploader from './components/ImageUploader.jsx'
import WebcamCapture from './components/WebcamCapture.jsx'
import PreviewCanvas from './components/PreviewCanvas.jsx'
import ResultPanel from './components/ResultPanel.jsx'

export default function App(){
  const [imageUrl,setImageUrl]=useState(null)
  const [loading,setLoading]=useState(false)
  const [error,setError]=useState('')
  const [results,setResults]=useState(null)

  async function run(file,preview){
    setImageUrl(preview); setResults(null); setError(''); setLoading(true)
    try{ const data = await analyzeImage(file); setResults(data) }
    catch{ setError('Something went wrong') }
    finally{ setLoading(false) }
  }

  return (<div className="container">
    <h2>Face Analysis (Demo Preview)</h2>
    <p className="muted">This version uses sample data (no backend yet). We will integrate FastAPI later.</p>
    <div className="grid2">
      <div className="card"><h3>Upload from device</h3><ImageUploader onSelected={run}/></div>
      <div className="card"><h3>Use your camera</h3><WebcamCapture onCapture={run}/></div>
    </div>
    {loading && <p>Analyzing… ⏳</p>}
    {error && <p className="err">{error}</p>}
    {imageUrl && <div className="card" style={{marginTop:16}}><PreviewCanvas imageUrl={imageUrl} results={results}/></div>}
    <div className="card" style={{marginTop:16}}><ResultPanel data={results}/></div>
  </div>)
}
