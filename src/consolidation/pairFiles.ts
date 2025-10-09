
export type DocPair = {
  base: string
  pdfUrl: string
  jsonUrl: string
  docType: string
}

export async function pairFiles(fileList: FileList): Promise<DocPair[]> {
  const files = Array.from(fileList)
  const byBase = new Map<string, Partial<DocPair>>()

  for (const f of files) {
    const base = f.name.replace(/\.(pdf|json|txt)$/i, '')
    const e = byBase.get(base) || { base }
    if (f.name.toLowerCase().endsWith('.pdf')) {
      e.pdfUrl = URL.createObjectURL(f)
    } else if (f.name.toLowerCase().match(/\.(json|txt)$/)) {
      e.jsonUrl = URL.createObjectURL(f)
      const m = f.name.match(/(invoice|lease|fds|guarantee|acceptance)/i)
      if (m) e.docType = m[1].toLowerCase()
    }
    byBase.set(base, e)
  }

  const out: DocPair[] = []
  for (const e of byBase.values()) {
    if (!e.pdfUrl || !e.jsonUrl || !e.base) continue
    const docType = e.docType || inferDocTypeFromName(e.base)
    out.push({ base: e.base, pdfUrl: e.pdfUrl, jsonUrl: e.jsonUrl, docType })
  }
  return out
}

function inferDocTypeFromName(s: string) {
  const m = s.match(/(invoice|lease|fds|guarantee|acceptance)/i)
  return m ? m[1].toLowerCase() : 'unknown'
}
