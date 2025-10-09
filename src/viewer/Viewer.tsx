
import React from 'react'
import type { AnyMsg, LoadDocMsg, HighlightMsg } from '../shared/messages'

export const Viewer: React.FC = () => {
  const [pdfUrl, setPdfUrl] = React.useState<string | null>(null)
  const [box, setBox] = React.useState<[number,number,number,number] | null>(null)
  const containerRef = React.useRef<HTMLDivElement>(null)

  React.useEffect(()=>{
    function onMsg(ev: MessageEvent) {
      if (ev.origin !== window.location.origin) return
      const msg = ev.data as AnyMsg
      if (msg.kind === 'LOAD_DOC') {
        const m = msg as LoadDocMsg
        setPdfUrl(m.pdfUrl)
        setBox(null)
      } else if (msg.kind === 'HIGHLIGHT_FIELD') {
        const m = msg as HighlightMsg
        setBox(m.bbox)
        // optional: scroll to center
        setTimeout(()=>{
          containerRef.current?.scrollTo({ top: 0, left: 0, behavior: 'smooth' })
        }, 50)
      }
    }
    window.addEventListener('message', onMsg)
    // handshake
    window.opener?.postMessage({ kind: 'READY', viewerId: crypto.randomUUID() }, window.location.origin)
    return ()=> window.removeEventListener('message', onMsg)
  },[])

  return (
    <div ref={containerRef} style={{height:'100vh', width:'100vw', overflow:'auto', background:'#111', color:'#fff'}}>
      <div style={{position:'relative', margin:'16px auto', width:'80%', height:'calc(100vh - 120px)', background:'#222', border:'1px solid #333'}}>
        {pdfUrl ? (
          <>
            <iframe src={pdfUrl} title="pdf" style={{position:'absolute', inset:0, width:'100%', height:'100%', border:'none', background:'#fff'}} />
            {box && (
              <div style={{
                position:'absolute',
                left: `${box[0]*100}%`,
                top: `${box[1]*100}%`,
                width: `${(box[2]-box[0])*100}%`,
                height: `${(box[3]-box[1])*100}%`,
                border: '3px solid #ff4dd2',
                boxShadow: '0 0 0 9999px rgba(255,77,210,0.15)',
                pointerEvents:'none'
              }} />
            )}
          </>
        ) : (
          <div style={{padding:24}}>Waiting for LOAD_DOC…</div>
        )}
      </div>
    </div>
  )
}
