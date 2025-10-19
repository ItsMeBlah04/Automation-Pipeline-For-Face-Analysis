import Webcam from 'react-webcam'
import { useRef, useState } from 'react'
export default function WebcamCapture({ onCapture }){
  const ref = useRef(null); const [shot,setShot]=useState(null)
  function capture(){
    const dataUrl = ref.current.getScreenshot(); if(!dataUrl) return
    fetch(dataUrl).then(res=>res.blob()).then(blob=>{
      const file = new File([blob],'capture.jpg',{type:'image/jpeg'})
      setShot(dataUrl); onCapture(file,dataUrl)
    })
  }
  return (<div>
    <Webcam ref={ref} screenshotFormat="image/jpeg" videoConstraints={{facingMode:'user'}}/>
    <div style={{marginTop:8}}><button onClick={capture}>Capture</button></div>
    {shot && <img src={shot} alt="shot" style={{marginTop:12}}/>}
  </div>)
}
