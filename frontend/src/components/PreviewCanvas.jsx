import { useEffect, useRef } from 'react'
export default function PreviewCanvas({ imageUrl, results }){
  const canvasRef = useRef(null)
  useEffect(()=>{
    if(!imageUrl) return
    const canvas = canvasRef.current, ctx = canvas.getContext('2d'), img = new Image()
    img.onload=()=>{
      canvas.width=img.width; canvas.height=img.height; ctx.drawImage(img,0,0)
      if(!results || !results.faces) return
      ctx.font='14px system-ui'
      results.faces.forEach(f=>{
        const [x,y,w,h]=f.box
        ctx.strokeStyle='#2563eb'; ctx.lineWidth=2; ctx.strokeRect(x,y,w,h)
        const tag=`${f.emotion.label} • ${f.gender.label} • ${f.age.label}`
        const pad=4, tw=ctx.measureText(tag).width+pad*2
        ctx.fillStyle='rgba(37,99,235,0.85)'; ctx.fillRect(x,y-22,tw,20)
        ctx.fillStyle='#fff'; ctx.fillText(tag,x+pad,y-6)
      })
    }
    img.src=imageUrl
  },[imageUrl,results])
  return <canvas ref={canvasRef}/>
}
