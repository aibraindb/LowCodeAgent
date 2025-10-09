
import type { DocPair } from './pairFiles'
import type { AnyMsg, LoadDocMsg } from '../shared/messages'

const ORIGIN = window.location.origin
const refs: Record<string, Window | null> = {}
const pending = new Map<string, DocPair>()

export function openOrAttach(pair: DocPair) {
  const name = `DOC_TAB_${pair.docType}`
  const url = `/viewer?docType=${encodeURIComponent(pair.docType)}`
  const child = window.open(url, name, 'noopener')
  refs[pair.docType] = child
  child?.focus()
  pending.set(name, pair)
}

export function sendToChild(win: Window | null, msg: AnyMsg) {
  try { win?.postMessage(msg, ORIGIN) } catch {}
}

export function getChild(docType: string) {
  const w = refs[docType]
  if (w && w.closed) {
    refs[docType] = null
    return null
  }
  return refs[docType]
}

window.addEventListener('message', (ev) => {
  if (ev.origin !== ORIGIN) return
  const msg = ev.data as AnyMsg
  if (msg && (msg as any).kind === 'READY') {
    const name = (ev.source as Window).name
    const pair = name && pending.get(name)
    if (pair) {
      const load: LoadDocMsg = { kind: 'LOAD_DOC', base: pair.base, docType: pair.docType, pdfUrl: pair.pdfUrl, jsonUrl: pair.jsonUrl }
      sendToChild(ev.source as Window, load)
      pending.delete(name!)
    }
  }
})
