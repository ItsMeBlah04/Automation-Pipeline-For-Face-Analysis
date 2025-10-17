// Temporary fake data until backend is ready.
export async function analyzeImage(file){
  await new Promise(r=>setTimeout(r,900))
  return {
    faces:[{
      box:[100,100,200,200],
      emotion:{label:'happy',score:0.95},
      age:{label:'18-24',score:0.87},
      gender:{label:'female',score:0.90}
    }],
    latency_ms:512
  }
}
