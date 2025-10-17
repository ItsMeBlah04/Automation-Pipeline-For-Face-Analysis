export default function ResultPanel({ data }){
  if(!data) return <p className="muted">Results will appear here.</p>
  const faces = data.faces || []
  return (<div>
    <div className="pill">Latency: {data.latency_ms ?? '—'} ms</div>
    {faces.length===0 && <p>No faces detected.</p>}
    {faces.map((f,i)=>(
      <div key={i} style={{marginTop:8}}>
        <strong>Face {i+1}</strong><br/>
        Emotion: {f.emotion.label} ({(f.emotion.score*100).toFixed(1)}%)<br/>
        Gender: {f.gender.label} ({(f.gender.score*100).toFixed(1)}%)<br/>
        Age: {f.age.label} ({(f.age.score*100).toFixed(1)}%)
      </div>
    ))}
  </div>)
}
