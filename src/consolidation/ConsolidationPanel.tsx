
import React from 'react'
import { pairFiles, type DocPair } from './pairFiles'
import { openOrAttach, getChild } from './OpenManager'
import type { HighlightMsg } from '../shared/messages'
import { JsonList } from '../components/JsonList'

export const ConsolidationPanel: React.FC = () => {
  const [pairs, setPairs] = React.useState<DocPair[]>([])
  const [selectedPair, setSelectedPair] = React.useState<DocPair|null>(null)
  const [json, setJson] = React.useState<any>(null)

  async function onFiles(e: React.ChangeEvent<HTMLInputElement>) {
    if (!e.target.files?.length) return
    const p = await pairFiles(e.target.files)
    setPairs(p)
  }

  async function selectPair(p: DocPair) {
    setSelectedPair(p)
    const j = await fetch(p.jsonUrl).then(r=>r.json())
    setJson(j)
  }

  function bboxFromNode(node: any): [number,number,number,number] | null {
    const verts = node?.fieldData?.bounding_poly?.normalized_vertices
    if (!verts) return null
    const xs = verts.map((v:any)=>Number(v.x||0)); const ys = verts.map((v:any)=>Number(v.y||0))
    return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
  }

  function onJsonClick(node: any) {
    if (!selectedPair) return
    const bbox = bboxFromNode(node)
    if (!bbox) return
    const child = getChild(selectedPair.docType)
    if (!child) {
      openOrAttach(selectedPair)
      setTimeout(()=>onJsonClick(node), 400) // retry shortly
      return
    }
    const msg: HighlightMsg = { kind: 'HIGHLIGHT_FIELD', base: selectedPair.base, bbox }
    child.postMessage(msg, window.location.origin)
  }

  return (
    <div style={{display:'grid', gridTemplateColumns:'320px 1fr', height:'100vh'}}>
      <div style={{borderRight:'1px solid #ccc', padding:12}}>
        <h3>Consolidation Panel</h3>
        <input type="file" multiple accept=".pdf,.json,.txt" onChange={onFiles}/>
        <div style={{marginTop:12}}>
          {pairs.map((p,i)=>(
            <div key={i} style={{display:'flex', alignItems:'center', gap:8, padding:'6px 0', borderBottom:'1px solid #eee'}}>
              <button onClick={()=>openOrAttach(p)}>Open</button>
              <button onClick={()=>selectPair(p)}>JSON</button>
              <span style={{fontFamily:'monospace'}}>{p.base}</span>
              <span style={{marginLeft:'auto', fontSize:12, background:'#eef', padding:'2px 6px', borderRadius:4}}>{p.docType}</span>
            </div>
          ))}
        </div>
      </div>
      <div>
        {json ? <JsonList json={json} onClick={onJsonClick}/> : <div style={{padding:24, color:'#666'}}>Load files, then click JSON to preview. Click a node to highlight in the viewer tab.</div>}
      </div>
    </div>
  )
}
