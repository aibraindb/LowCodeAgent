
import React from 'react'

type Props = {
  json: any
  onClick: (node: any) => void
}

// Extract elements with normalized vertices similar to your code
function flatten(json: any) {
  const out: any[] = []
  const root = Array.isArray(json) ? json[0] : json
  const props = Array.isArray(root?.properties) ? root.properties[0] : root?.properties || {}
  const meta = props?.metadataMap || {}
  const pages = props?.pages || []

  Object.entries(meta).forEach(([key, field]: any) => {
    const verts = field?.bounding_poly?.normalized_vertices
    if (verts) out.push({ key, value: field.value, fieldData: field })
  })
  pages.forEach((p: any, i: number) => {
    ;(p.elements || []).forEach((el: any, j: number) => {
      const verts = el?.boundingBox?.normalizedVertices
      if (verts) out.push({ key: `page_${i+1}_el_${j}`, value: el.content, fieldData: {
        bounding_poly: { normalized_vertices: verts }, confidence: el.confidence, source: 'element'
      }})
    })
  })
  return out
}

export const JsonList: React.FC<Props> = ({ json, onClick }) => {
  const rows = React.useMemo(() => flatten(json), [json])
  return (
    <div style={{height:'100%', overflow:'auto', fontFamily:'monospace', fontSize:12}}>
      {rows.map((r,idx) => (
        <div key={idx} onClick={()=>onClick(r)} style={{padding:'6px 8px', borderBottom:'1px solid #eee', cursor:'pointer'}}>
          <div><b>{r.key}</b></div>
          <div style={{color:'#555', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{String(r.value||'')}</div>
        </div>
      ))}
    </div>
  )
}
