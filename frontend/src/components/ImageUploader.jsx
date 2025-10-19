import { useRef, useState } from 'react'
export default function ImageUploader({ onSelected }){
  const inputRef = useRef(null)
  const [preview,setPreview] = useState(null)
  function setFile(file){ const url = URL.createObjectURL(file); setPreview(url); onSelected(file,url) }
  function handleChange(e){ const f=e.target.files?.[0]; if(f) setFile(f) }
  function handleDrop(e){ e.preventDefault(); const f=e.dataTransfer.files?.[0]; if(f) setFile(f) }
  return (<div onDragOver={(e)=>e.preventDefault()} onDrop={handleDrop}>
    <button onClick={()=>inputRef.current.click()}>Choose image</button>
    <input ref={inputRef} type="file" accept="image/*" style={{display:'none'}} onChange={handleChange}/>
    {preview && <img src={preview} alt="preview" style={{marginTop:12}}/>}
  </div>)
}
